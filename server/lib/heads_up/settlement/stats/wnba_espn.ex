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
  alias HeadsUp.Settlement.Stats.WindowScan
  alias HeadsUp.Sports.Espn.{Client, Parse}

  # Documented boxscore column order — fallback when a row omits its `labels`.
  @default_labels ~w(MIN PTS FG 3PT FT REB AST TO STL BLK OREB DREB PF +/-)

  @impl true
  def stats_final?(%Window{sport: sport} = window) do
    case WindowScan.events(client(), window) do
      {:error, reason} ->
        Logger.info("WnbaEspn.stats_final? deferring duel #{window.duel_id}: #{inspect(reason)}")
        false

      {:ok, []} ->
        # No games in the window — nothing to wait for; settles to a 0–0 tie.
        true

      {:ok, events} ->
        Enum.all?(events, & &1.final?) and boxscores_reachable?(sport, events)
    end
  end

  @impl true
  def fetch_stats(players, %Window{} = window) when is_list(players), do: do_fetch(players, window, true)

  @impl true
  def fetch_live_stats(players, %Window{} = window) when is_list(players), do: do_fetch(players, window, false)

  @impl true
  def live_games(%Window{} = window), do: WindowScan.game_counts(client(), window)

  # Sum boxscores across in-window games. `only_final?` true (settlement) counts
  # only FINAL games; false (live) includes in-progress boxscores too.
  defp do_fetch(players, %Window{sport: sport} = window, only_final?) do
    ids =
      case WindowScan.events(client(), window) do
        {:ok, events} -> events |> include(only_final?) |> Enum.map(& &1.id)
        {:error, _} -> []
      end

    summed = sum_across_games(sport, ids)
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

  defp include(events, true), do: Enum.filter(events, & &1.final?)
  defp include(events, false), do: events

  # --- boxscores ----------------------------------------------------------

  defp boxscores_reachable?(sport, events) do
    events
    |> Enum.map(& &1.id)
    |> Enum.all?(fn id -> match?({:ok, _}, fetch_boxscore(sport, id)) end)
  end

  defp sum_across_games(sport, event_ids) do
    Enum.reduce(event_ids, %{}, fn id, acc ->
      case fetch_boxscore(sport, id) do
        {:ok, by_eid} -> merge_sum(acc, by_eid)
        # stats_final? already proved reachability; a late failure just scores 0.
        {:error, _} -> acc
      end
    end)
  end

  # %{espn_id_string => %{category => total}} for one game.
  defp fetch_boxscore(sport, event_id) do
    case client().summary(sport, event_id) do
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
