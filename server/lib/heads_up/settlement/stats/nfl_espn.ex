defmodule HeadsUp.Settlement.Stats.NflEspn do
  @moduledoc """
  The live NFL `StatsProvider`. Scores from each in-window game's **box score**
  (`Sports.BoxScore`, the same parse the game-detail screen renders), not from
  per-player game logs. Three reasons football differs from MLB here:

    * **Completeness.** ESPN publishes an empty game log for some active
      players — Travis Kelce among them — so a game-log-only provider would
      score a star who actually played as a zero. The box score lists everyone
      who took a snap.
    * **Live.** Box scores tick during the game; game logs only publish once it
      ends. Football Sunday is the marquee use case for the live matchup.
    * **Cost.** One request per game instead of one per drafted player, and
      both rosters share the same handful of games.

  A player appears in several football tables (a quarterback in passing AND
  rushing), so their categories are summed across every row carrying their
  athlete id.

  - `stats_final?/1` gates on the scoreboard: settlement waits until every
    in-window game is `STATUS_FINAL`. A zero-game window settles to a 0–0 tie.
  - `fetch_stats/2` sums FINAL games only; `fetch_live_stats/2` also counts
    games in progress.

  A football slate is a DAY, not a week — the same shape as every other sport
  here. Thursday, Sunday and Monday are separate slates, which is how DFS runs
  football and keeps a duel settling the night it is drafted instead of five
  days later.

  The ESPN client is injectable via
  `config :heads_up, #{inspect(__MODULE__)}, client: Mod` for offline tests.
  """
  @behaviour HeadsUp.Settlement.StatsProvider

  require Logger

  alias HeadsUp.Contests.Scoring
  alias HeadsUp.Settlement.Window
  alias HeadsUp.Settlement.Stats.WindowScan
  alias HeadsUp.Sports.BoxScore
  alias HeadsUp.Sports.Espn.Client

  @impl true
  def stats_final?(%Window{} = window) do
    case WindowScan.events(client(), window) do
      {:error, reason} ->
        Logger.info("NflEspn.stats_final? deferring duel #{window.duel_id}: #{inspect(reason)}")
        false

      {:ok, []} ->
        true

      {:ok, events} ->
        Enum.all?(events, & &1.final?)
    end
  end

  @impl true
  def fetch_stats(players, %Window{} = window) when is_list(players) do
    score(players, window, &(&1.final?))
  end

  # Live counts anything that has kicked off — final games plus the one being
  # played right now. "pre" games contribute nothing yet.
  @impl true
  def fetch_live_stats(players, %Window{} = window) when is_list(players) do
    score(players, window, &(&1.state != "pre"))
  end

  @impl true
  def live_games(%Window{} = window), do: WindowScan.game_counts(client(), window)

  @impl true
  def team_states(%Window{} = window), do: WindowScan.team_states(client(), window)

  # --- scoring ------------------------------------------------------------

  defp score(players, %Window{sport: sport} = window, keep?) do
    cats = sport |> Scoring.default_rules() |> Map.keys()
    base = Map.new(cats, &{&1, 0})

    by_athlete =
      case WindowScan.events(client(), window) do
        {:ok, events} ->
          events
          |> Enum.filter(keep?)
          |> Enum.map(& &1.id)
          |> Enum.reduce(%{}, fn event_id, acc -> merge_event(acc, sport, event_id, cats) end)

        {:error, reason} ->
          Logger.info("NflEspn could not read the scoreboard for duel #{window.duel_id}: #{inspect(reason)}")
          %{}
      end

    Map.new(players, fn p -> {p.id, Map.get(by_athlete, to_string(p.external_id), base)} end)
  end

  # Fold one game's box score into %{espn_athlete_id => category totals}. A
  # player shows up in several tables, so their rows accumulate rather than
  # overwrite. An unreadable game contributes nothing instead of failing the
  # whole settlement — the missing points would be identical for both rosters.
  defp merge_event(acc, sport, event_id, cats) do
    case BoxScore.for_event(sport, event_id, client: client()) do
      {:ok, box} ->
        for team <- box.teams, group <- team.groups, row <- group.rows, reduce: acc do
          inner -> add_row(inner, row, cats)
        end

      {:error, reason} ->
        Logger.info("NflEspn skipping unreadable box score #{event_id}: #{inspect(reason)}")
        acc
    end
  end

  defp add_row(acc, %{external_id: eid}, _cats) when eid in [nil, ""], do: acc

  defp add_row(acc, row, cats) do
    Map.update(acc, row.external_id, totals(row.line, cats), fn have ->
      Enum.reduce(cats, have, fn cat, a -> Map.update!(a, cat, &(&1 + Map.get(row.line, cat, 0))) end)
    end)
  end

  defp totals(line, cats), do: Map.new(cats, &{&1, Map.get(line, &1, 0)})

  defp client do
    Application.get_env(:heads_up, __MODULE__, [])
    |> Keyword.get(:client, Client)
  end
end
