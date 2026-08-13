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
  perfectly scoped one.

  Two shapes share that one scan: `upcoming/2` gives ET DAYS (basketball,
  baseball) and `weeks/2` gives ESPN WEEKS (football, whose teams play once a
  week). Both resolve to a list of ET dates, which is what a duel stores.
  """

  require Logger

  alias HeadsUp.Sports.Espn.Client

  # ET = UTC-4 through the WNBA/MLB season (matches WindowScan/PoolFilter).
  @et_offset_seconds -4 * 3600
  @days_ahead 7
  # Far enough to always show a few whole football weeks, including the gap
  # between the preseason opener and week 2.
  @weeks_ahead_days 24
  @ttl_ms 15 * 60 * 1000
  # How stale a schedule may get before an outage is worse than an empty
  # picker. A day-old schedule can be genuinely wrong (postponements, flexes).
  @max_stale_ms 6 * 60 * 60 * 1000

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
  The upcoming WEEKS for a sport whose teams play once a week — football.

  A football day slate is structurally thin: a team plays a single game, so a
  Thursday offers two teams and a Monday two more. The week is the honest unit,
  and it is what everyone already means by "week 3". Each entry is
  `%{key, season_type, week, label, dates, games, teams, upcoming,
  upcoming_teams}`; `dates` are the ET days the week actually has games on, and
  they are what the duel stores and scores.

  Weeks whose games have all started are dropped — you cannot draft into them.
  """
  def weeks(sport, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    today = et_date(now)
    to = Date.add(today, @weeks_ahead_days)

    with {:ok, events} <- scan(sport, today, to, opts) do
      {:ok,
       events
       |> Enum.filter(&(&1.season_type && &1.week))
       |> Enum.group_by(&{&1.season_type, &1.week})
       |> Enum.map(fn {{stype, wk}, evs} -> week_entry(stype, wk, evs) end)
       |> Enum.filter(&(&1.upcoming > 0))
       |> Enum.sort_by(& &1.dates |> List.first())}
    end
  end

  defp week_entry(season_type, week, events) do
    pre = Enum.filter(events, &(&1.state == "pre"))

    %{
      key: "#{season_type}-#{week}",
      season_type: season_type,
      week: week,
      label: week_label(season_type, week),
      # Only days that actually have games — an empty Friday never enters the
      # scoring window, so a duel can't be scored against a day it didn't pick.
      dates: events |> Enum.map(& &1.date) |> Enum.uniq() |> Enum.sort(Date),
      # The earliest day still open to draft from. Mid-week this is AFTER the
      # week's first day: on a Saturday, Thursday's game is long done but
      # Sunday's is not, and a duel created then is perfectly honest.
      first_upcoming_date: pre |> Enum.map(& &1.date) |> Enum.min(Date, fn -> nil end),
      games: length(events),
      teams: events |> Enum.flat_map(& &1.teams) |> Enum.uniq(),
      upcoming: length(pre),
      upcoming_teams: pre |> Enum.flat_map(& &1.teams) |> Enum.uniq()
    }
  end

  defp week_label(1, week), do: "Preseason Wk #{week}"
  defp week_label(3, week), do: "Playoffs Wk #{week}"
  defp week_label(_, week), do: "Week #{week}"

  @doc """
  True when a sport's slates are weeks rather than days. Football only: its
  teams play once a week, so a single night is two teams, not a league.
  """
  def week_shaped?(sport), do: sport == "nfl"

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

    # Stubs bypass the cache so they can't poison other tests. `cache: true`
    # opts a stub back IN, which is the only way to exercise the
    # serve-stale-on-failure path without reaching the real network.
    if client == Client or Keyword.get(opts, :cache, false) do
      cached_scan(client, sport, from, to)
    else
      do_scan(client, sport, from, to)
    end
  end

  defp cached_scan(client, sport, from, to) do
    key = {__MODULE__, sport, from}
    cached = :persistent_term.get(key, nil)

    case cached do
      {ts, {:ok, _} = result} ->
        if System.monotonic_time(:millisecond) - ts < @ttl_ms do
          result
        else
          refresh(client, key, sport, from, to, cached)
        end

      _ ->
        refresh(client, key, sport, from, to, cached)
    end
  end

  # On a feed failure, keep serving the last good answer rather than nothing.
  # A schedule is slow-moving: an hour-old copy of "who plays Thursday" is
  # almost always right, and it is certainly better than an empty slate picker
  # while ESPN is unreachable. Errors themselves are never cached.
  defp refresh(client, key, sport, from, to, cached) do
    case do_scan(client, sport, from, to) do
      {:ok, _} = ok ->
        :persistent_term.put(key, {System.monotonic_time(:millisecond), ok})
        ok

      {:error, _} = err ->
        stale_or(cached, err)
    end
  end

  defp stale_or({ts, {:ok, events}}, err) do
    age_ms = System.monotonic_time(:millisecond) - ts

    if age_ms <= @max_stale_ms do
      Logger.warning("Slate feed unreachable — serving a #{div(age_ms, 60_000)}m-old schedule")
      {:ok, Enum.map(events, &age_out/1)}
    else
      err
    end
  end

  defp stale_or(_none, err), do: err

  # The one part of a cached scoreboard that genuinely rots is a game's STATE.
  # Serving a stale "pre" would offer a team whose game has already kicked off,
  # which is the hindsight exploit the slate exists to prevent. Kickoff time is
  # known locally, so anything that should have started by now is treated as
  # started — conservative in the only direction that matters.
  defp age_out(%{date: date, state: "pre"} = event) do
    if Date.compare(date, et_date(DateTime.utc_now())) == :lt do
      %{event | state: "post"}
    else
      event
    end
  end

  defp age_out(event), do: event

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
    %{
      date: date,
      teams: teams,
      state: get_in(event, ["status", "type", "state"]) || "pre",
      # Football's slate unit. ESPN season types: 1 = preseason, 2 = regular,
      # 3 = post. nil for the sports we scope by day.
      season_type: get_in(event, ["season", "type"]),
      week: get_in(event, ["week", "number"])
    }
  end

  defp et_date(dt), do: dt |> DateTime.add(@et_offset_seconds, :second) |> DateTime.to_date()

  defp client, do: Application.get_env(:heads_up, :slate_client, Client)
end
