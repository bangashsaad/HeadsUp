defmodule HeadsUp.Settlement.Stats.WnbaEspn do
  @moduledoc """
  The live WNBA `StatsProvider` (Phase 5b). Turns a duel's frozen scoring
  `Window` into real per-player stat lines from the ESPN feed.

  Both callbacks share one scan: enumerate the ET calendar days the window
  touches, pull each day's scoreboard, and keep the events whose kickoff falls
  inside `[opens_at, closes_at]`.

  - `stats_final?/1` gates settlement. It returns `true` only when EVERY
    in-window game is `STATUS_FINAL` **and** every one of those boxscores is
    reachable — so the no-error-branch `fetch_stats/1` that runs next can never
    corrupt a settle. A window with ZERO games (dev's 120s window, an off day)
    is reported final (nothing to wait for) and scores everyone 0 → a tie.
    Any fetch failure → `false` (defer; the worker re-sweeps).
  - `fetch_stats/2` sums each athlete's stats across all in-window FINAL games,
    joins ESPN athlete id → our `player.external_id`, and emits a full
    seven-category line for EVERY input player (zeros for DNP / not-found).

  The ESPN client is injectable via
  `config :heads_up, #{inspect(__MODULE__)}, client: Mod` for offline tests.
  """
  @behaviour HeadsUp.Settlement.StatsProvider

  require Logger

  alias HeadsUp.Contests.Scoring
  alias HeadsUp.Settlement.Window
  alias HeadsUp.Sports.Espn.{Client, Parse}

  # The whole WNBA season (May–Sep) is EDT = UTC−4; no tzdata needed.
  @et_offset_seconds -4 * 3600
  # A sane upper bound so a mis-built months-long window can't hammer ESPN.
  @max_days 35
  # Documented boxscore column order — fallback when a row omits its `labels`.
  @default_labels ~w(MIN PTS FG 3PT FT REB AST TO STL BLK OREB DREB PF +/-)

  @impl true
  def stats_final?(%Window{} = window) do
    case window_events(window) do
      {:error, reason} ->
        Logger.info("WnbaEspn.stats_final? deferring duel #{window.duel_id}: #{inspect(reason)}")
        false

      {:ok, []} ->
        # No games in the window — nothing to wait for; settles to a 0–0 tie.
        true

      {:ok, events} ->
        Enum.all?(events, & &1.final?) and boxscores_reachable?(events)
    end
  end

  @impl true
  def fetch_stats(players, %Window{} = window) when is_list(players) do
    final_ids =
      case window_events(window) do
        {:ok, events} -> events |> Enum.filter(& &1.final?) |> Enum.map(& &1.id)
        {:error, _} -> []
      end

    summed = sum_across_games(final_ids)
    cats = categories(window.sport)
    eid_to_pid = Map.new(players, &{&1.external_id, &1.id})
    base = Map.new(players, &{&1.id, zeros(cats)})

    Enum.reduce(summed, base, fn {espn_id, line}, acc ->
      case Map.get(eid_to_pid, espn_id) do
        nil -> acc
        pid -> Map.put(acc, pid, Map.merge(zeros(cats), Map.take(line, cats)))
      end
    end)
  end

  # --- window scan --------------------------------------------------------

  # In-window events as %{id, final?}, or {:error, reason} if any day's
  # scoreboard can't be fetched (can't prove finality → must defer).
  defp window_events(%Window{opens_at: o, closes_at: c}) do
    case et_dates(o, c) do
      {:error, reason} ->
        {:error, reason}

      {:ok, dates} ->
        Enum.reduce_while(dates, {:ok, []}, fn date, {:ok, acc} ->
          ymd = Calendar.strftime(date, "%Y%m%d")

          case client().scoreboard(ymd) do
            {:ok, body} -> {:cont, {:ok, acc ++ parse_events(body, o, c)}}
            {:error, reason} -> {:halt, {:error, {:scoreboard, ymd, reason}}}
          end
        end)
    end
  end

  defp parse_events(body, opens_at, closes_at) do
    body
    |> Map.get("events", [])
    |> List.wrap()
    |> Enum.filter(fn e -> in_window?(e["date"], opens_at, closes_at) end)
    |> Enum.map(fn e ->
      %{id: to_string(e["id"]), final?: get_in(e, ["status", "type", "name"]) == "STATUS_FINAL"}
    end)
  end

  defp et_dates(o, c) do
    start_d = o |> DateTime.add(@et_offset_seconds, :second) |> DateTime.to_date()
    end_d = c |> DateTime.add(@et_offset_seconds, :second) |> DateTime.to_date()
    span = Date.diff(end_d, start_d)

    cond do
      span < 0 -> {:ok, []}
      span > @max_days -> {:error, {:window_too_wide, span}}
      true -> {:ok, Enum.map(0..span, &Date.add(start_d, &1))}
    end
  end

  defp in_window?(iso, opens_at, closes_at) do
    case parse_dt(iso) do
      {:ok, dt} ->
        DateTime.compare(dt, opens_at) != :lt and DateTime.compare(dt, closes_at) != :gt

      :error ->
        false
    end
  end

  # ESPN emits "2026-06-30T23:00Z" (no seconds) as well as full ISO8601.
  defp parse_dt(iso) when is_binary(iso) do
    fixed = Regex.replace(~r/T(\d{2}):(\d{2})Z$/, iso, "T\\1:\\2:00Z")

    case DateTime.from_iso8601(fixed) do
      {:ok, dt, _} -> {:ok, dt}
      _ -> :error
    end
  end

  defp parse_dt(_), do: :error

  # --- boxscores ----------------------------------------------------------

  defp boxscores_reachable?(events) do
    events
    |> Enum.map(& &1.id)
    |> Enum.all?(fn id -> match?({:ok, _}, fetch_boxscore(id)) end)
  end

  defp sum_across_games(event_ids) do
    Enum.reduce(event_ids, %{}, fn id, acc ->
      case fetch_boxscore(id) do
        {:ok, by_eid} -> merge_sum(acc, by_eid)
        # stats_final? already proved reachability; a late failure just scores 0.
        {:error, _} -> acc
      end
    end)
  end

  # %{espn_id_string => %{category => total}} for one game.
  defp fetch_boxscore(event_id) do
    case client().summary(event_id) do
      {:ok, body} ->
        lines =
          body
          |> get_in(["boxscore", "players"])
          |> List.wrap()
          |> Enum.reduce(%{}, fn team, acc ->
            group = team["statistics"] |> List.wrap() |> List.first()
            labels = (group && group["labels"]) || @default_labels
            athletes = (group && group["athletes"]) || []

            Enum.reduce(athletes, acc, fn a, acc2 ->
              eid = get_in(a, ["athlete", "id"])
              stats = a["stats"] || []

              if eid && stats != [] do
                Map.put(acc2, to_string(eid), extract_line(labels, stats))
              else
                acc2
              end
            end)
          end)

        {:ok, lines}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_line(labels, stats) do
    %{
      "point" => Parse.to_int(Parse.stat_value(labels, stats, "PTS")),
      "rebound" => Parse.to_int(Parse.stat_value(labels, stats, "REB")),
      "assist" => Parse.to_int(Parse.stat_value(labels, stats, "AST")),
      "steal" => Parse.to_int(Parse.stat_value(labels, stats, "STL")),
      "block" => Parse.to_int(Parse.stat_value(labels, stats, "BLK")),
      "turnover" => Parse.to_int(Parse.stat_value(labels, stats, "TO")),
      "three_made" => Parse.made_from(Parse.stat_value(labels, stats, "3PT"))
    }
  end

  defp merge_sum(acc, by_eid) do
    Enum.reduce(by_eid, acc, fn {eid, line}, acc2 ->
      Map.update(acc2, eid, line, fn existing ->
        Map.merge(existing, line, fn _k, a, b -> a + b end)
      end)
    end)
  end

  # --- helpers ------------------------------------------------------------

  defp categories(sport), do: sport |> Scoring.default_rules() |> Map.keys()
  defp zeros(cats), do: Map.new(cats, &{&1, 0})

  defp client do
    Application.get_env(:heads_up, __MODULE__, [])
    |> Keyword.get(:client, Client)
  end
end
