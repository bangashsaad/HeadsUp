defmodule HeadsUp.Sports.Slate do
  @moduledoc """
  A slate = one ET calendar day of games for a sport. A slate-scoped duel
  drafts only players whose teams play that day and scores only that day's
  games — no more drafting someone who doesn't even play tonight.

  One cached range-scoreboard call answers both questions the feature needs:
  "which days can I pick?" (the challenge form's slate chips) and "which teams
  play on day D?" (the create-time pool guard + the draft board filter).

  Every function fails OPEN: `{:error, reason}` means the feed was unreachable
  and callers should fall back to un-scoped behavior — a working duel beats a
  perfectly scoped one. The model is deliberately day-shaped but NFL-ready:
  a week slate is just a wider date range with the same teams-per-day scan.
  """

  alias HeadsUp.Sports.Espn.Client

  # ET = UTC-4 through the WNBA/MLB season (matches WindowScan/PoolFilter).
  @et_offset_seconds -4 * 3600
  @days_ahead 7
  @ttl_ms 15 * 60 * 1000

  @doc """
  The next #{@days_ahead + 1} ET days, each as `%{date, games, teams}` (zero-game
  days included so pickers can dim them). `{:error, reason}` on feed failure.
  """
  def upcoming(sport, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    today = et_date(now)
    to = Date.add(today, @days_ahead)

    with {:ok, events} <- scan(sport, today, to, opts) do
      by_day = Enum.group_by(events, & &1.date)

      {:ok,
       for d <- Date.range(today, to) do
         evs = Map.get(by_day, d, [])
         pre = Enum.filter(evs, &(&1.state == "pre"))

         %{
           date: d,
           games: length(evs),
           teams: evs |> Enum.flat_map(& &1.teams) |> Enum.uniq(),
           # Not-yet-tipped games only — what a duel created NOW could still
           # honestly draft. For future days this equals games/teams; for
           # today it shrinks as the night plays out.
           upcoming: length(pre),
           upcoming_teams: pre |> Enum.flat_map(& &1.teams) |> Enum.uniq()
         }
       end}
    end
  end

  @doc """
  One ET day's slate as `{:ok, %{date, games, teams}}` (a date outside the
  scanned range comes back with zero games). `{:error, reason}` on feed failure.
  """
  def on(sport, %Date{} = date, opts \\ []) do
    empty = %{date: date, games: 0, teams: [], upcoming: 0, upcoming_teams: []}

    with {:ok, days} <- upcoming(sport, opts) do
      {:ok, Enum.find(days, empty, &(&1.date == date))}
    end
  end

  @doc "Today's ET date (the earliest pickable slate)."
  def today(now \\ DateTime.utc_now()), do: et_date(now)

  @doc "The last pickable slate date (#{@days_ahead} days out)."
  def horizon(now \\ DateTime.utc_now()), do: now |> et_date() |> Date.add(@days_ahead)

  # --- scan + cache ---------------------------------------------------------

  # A single "YYYYMMDD-YYYYMMDD" scoreboard call, parsed to per-event
  # %{date: et_date, teams: [abbrev]}. Cached ~15 min per (sport, day-window).
  # ANY non-default client (opts injection or app-env override — both are
  # test-only) bypasses the cache so stubs can't poison other tests.
  defp scan(sport, from, to, opts) do
    client = Keyword.get(opts, :client, client())

    if client == Client do
      cached_scan(sport, from, to)
    else
      do_scan(client, sport, from, to)
    end
  end

  defp cached_scan(sport, from, to) do
    key = {__MODULE__, sport, from}

    case :persistent_term.get(key, nil) do
      {ts, result} when result != nil ->
        if System.monotonic_time(:millisecond) - ts < @ttl_ms do
          result
        else
          refresh(key, sport, from, to)
        end

      _ ->
        refresh(key, sport, from, to)
    end
  end

  defp refresh(key, sport, from, to) do
    case do_scan(client(), sport, from, to) do
      {:ok, _} = ok ->
        :persistent_term.put(key, {System.monotonic_time(:millisecond), ok})
        ok

      # Feed errors are never cached — the next caller retries.
      {:error, _} = err ->
        err
    end
  end

  defp do_scan(client, sport, from, to) do
    if Client.supported?(sport) do
      range = "#{Calendar.strftime(from, "%Y%m%d")}-#{Calendar.strftime(to, "%Y%m%d")}"

      # limit: ESPN caps range responses at 100 events by default; a full MLB
      # week is bigger, and the dropped tail would hollow out late-week slates.
      with {:ok, body} <- client.scoreboard(sport, range, limit: 300) do
        events =
          body
          |> Map.get("events", [])
          |> List.wrap()
          |> Enum.map(&parse_event/1)
          |> Enum.reject(&is_nil(&1.date))

        {:ok, events}
      end
    else
      {:error, :unsupported_sport}
    end
  end

  defp parse_event(event) do
    # ESPN emits "2026-06-30T23:00Z" (no seconds) as well as full ISO8601 —
    # same normalization as WindowScan.parse_dt/1.
    iso = Regex.replace(~r/T(\d{2}):(\d{2})Z$/, event["date"] || "", "T\\1:\\2:00Z")

    date =
      case DateTime.from_iso8601(iso) do
        {:ok, dt, _} -> et_date(dt)
        _ -> nil
      end

    teams =
      event
      |> get_in(["competitions", Access.at(0), "competitors"])
      |> List.wrap()
      |> Enum.map(&get_in(&1, ["team", "abbreviation"]))
      |> Enum.reject(&is_nil/1)

    # Missing status (stubs, feed quirks) counts as not-yet-tipped: unknown
    # must stay draftable (fail open), same spirit as everything else here.
    %{date: date, teams: teams, state: get_in(event, ["status", "type", "state"]) || "pre"}
  end

  defp et_date(dt), do: dt |> DateTime.add(@et_offset_seconds, :second) |> DateTime.to_date()

  defp client, do: Application.get_env(:heads_up, :slate_client, Client)
end
