defmodule HeadsUp.Settlement.Stats.MlbEspn do
  @moduledoc """
  The live MLB `StatsProvider`. Unlike the basketball provider (which reads each
  game's boxscore), MLB scores from each drafted player's ESPN **game log** — the
  baseball boxscore omits doubles/triples/steals, but the gamelog carries the full
  line the `@mlb` scoring chart needs. Per-game parsing is the shared
  `Sports.Gamelog`, so a player's profile, projection, and duel score all agree.

  - `stats_final?/1` gates on the scoreboard: settlement waits until every
    in-window game is `STATUS_FINAL`. A zero-game window settles to a 0–0 tie.
  - `fetch_stats/2` pulls each (numeric-id) player's game log, keeps the games
    whose event id is an in-window FINAL game, and sums their stat lines into the
    full `@mlb` category set (zeros for DNP / no-feed players).

  The ESPN client is injectable via
  `config :heads_up, #{inspect(__MODULE__)}, client: Mod` for offline tests.
  """
  @behaviour HeadsUp.Settlement.StatsProvider

  require Logger

  alias HeadsUp.Contests.Scoring
  alias HeadsUp.Settlement.Window
  alias HeadsUp.Settlement.Stats.WindowScan
  alias HeadsUp.Sports.Espn.Client
  alias HeadsUp.Sports.Gamelog

  @impl true
  def stats_final?(%Window{} = window) do
    case WindowScan.events(client(), window) do
      {:error, reason} ->
        Logger.info("MlbEspn.stats_final? deferring duel #{window.duel_id}: #{inspect(reason)}")
        false

      {:ok, []} ->
        true

      {:ok, events} ->
        Enum.all?(events, & &1.final?)
    end
  end

  @impl true
  def fetch_stats(players, %Window{sport: sport} = window) when is_list(players) do
    final_ids =
      case WindowScan.events(client(), window) do
        {:ok, events} -> events |> Enum.filter(& &1.final?) |> Enum.map(& &1.id) |> MapSet.new()
        {:error, _} -> MapSet.new()
      end

    cats = sport |> Scoring.default_rules() |> Map.keys()
    Map.new(players, fn p -> {p.id, player_line(sport, p, final_ids, cats)} end)
  end

  # Baseball game logs only publish after a game ends, so "live" == completed
  # games so far (mid-game lines aren't available); reuse the final path.
  @impl true
  def fetch_live_stats(players, %Window{} = window) when is_list(players), do: fetch_stats(players, window)

  @impl true
  def live_games(%Window{} = window), do: WindowScan.game_counts(client(), window)

  @impl true
  def team_states(%Window{} = window), do: WindowScan.team_states(client(), window)

  defp player_line(sport, player, final_ids, cats) do
    base = Map.new(cats, &{&1, 0})

    with true <- numeric?(player.external_id),
         {:ok, body} <- client().gamelog(sport, player.external_id) do
      sport
      |> Gamelog.parse(body)
      |> Enum.filter(fn g -> MapSet.member?(final_ids, to_string(g.event_id)) end)
      |> Enum.reduce(base, fn g, acc -> add_line(acc, g.line, cats) end)
    else
      _ -> base
    end
  end

  defp add_line(acc, line, cats) do
    Enum.reduce(cats, acc, fn cat, a -> Map.update!(a, cat, &(&1 + Map.get(line, cat, 0))) end)
  end

  defp numeric?(eid), do: is_binary(eid) and Regex.match?(~r/^\d+$/, eid)

  defp client do
    Application.get_env(:heads_up, __MODULE__, [])
    |> Keyword.get(:client, Client)
  end
end
