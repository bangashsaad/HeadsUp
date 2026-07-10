defmodule HeadsUp.Settlement.Stats.Mock do
  @moduledoc """
  Deterministic mock stats for stage 5a. A player's stat line is a pure function
  of `player.id` (and position), so the same player always yields the same
  numbers — reproducible tests and idempotent re-sweeps. Lines are position-aware
  (a QB throws, an RB rushes, a center rebounds) and keyed by exactly the sport's
  `Contests.Scoring` chart categories. ~6% of players (id rem 17 == 0) score all
  zeros, exercising the locked injured/benched draft-risk rule. Always reports
  the window as final.
  """
  @behaviour HeadsUp.Settlement.StatsProvider

  alias HeadsUp.Contests.Scoring
  alias HeadsUp.Settlement.Window
  alias HeadsUp.Sports.Player

  @impl true
  def stats_final?(%Window{}), do: true

  @impl true
  def fetch_stats(players, %Window{}) when is_list(players) do
    Map.new(players, fn %Player{} = p -> {p.id, line_for(p)} end)
  end

  @impl true
  def fetch_live_stats(players, %Window{} = window), do: fetch_stats(players, window)

  @impl true
  def live_games(%Window{}), do: %{final: 1, live: 0, upcoming: 0}

  @impl true
  def team_states(%Window{}), do: %{}

  defp line_for(%Player{} = p) do
    blank? = rem(p.id, 17) == 0
    cats = Map.keys(Scoring.default_rules(p.sport))

    Map.new(cats, fn cat ->
      {cat, if(blank?, do: 0, else: stat_value(p, cat))}
    end)
  end

  # Deterministic non-negative value within the position-appropriate range.
  defp stat_value(%Player{} = p, cat) do
    {lo, hi} = range(p.sport, p.position, cat)

    cond do
      hi <= lo -> lo
      true -> lo + rem(:erlang.phash2({p.id, cat}), hi - lo + 1)
    end
  end

  # --- ranges (inclusive) keyed off sport + position; {0,0} => not applicable --

  defp range(sport, pos, cat) when sport in ["nba", "wnba"] do
    cond do
      cat == "point" -> tier(pos, {8, 30}, {6, 24}, {6, 20})
      cat == "rebound" -> tier(pos, {1, 5}, {4, 10}, {6, 14})
      cat == "assist" -> tier(pos, {3, 11}, {1, 5}, {0, 3})
      cat == "steal" -> {0, 3}
      cat == "block" -> tier(pos, {0, 1}, {0, 2}, {0, 3})
      cat == "turnover" -> {0, 5}
      cat == "three_made" -> tier(pos, {0, 5}, {0, 3}, {0, 2})
      true -> {0, 0}
    end
  end

  defp range("nfl", pos, cat) do
    case {pos, cat} do
      {"QB", "passing_yards"} -> {150, 380}
      {"QB", "passing_td"} -> {0, 4}
      {"QB", "interception"} -> {0, 2}
      {"QB", "rushing_yards"} -> {0, 40}
      {"RB", "rushing_yards"} -> {30, 140}
      {"RB", "rushing_td"} -> {0, 2}
      {"RB", "reception"} -> {1, 6}
      {"RB", "receiving_yards"} -> {10, 50}
      {"WR", "reception"} -> {3, 11}
      {"WR", "receiving_yards"} -> {30, 130}
      {"WR", "receiving_td"} -> {0, 2}
      {"TE", "reception"} -> {2, 8}
      {"TE", "receiving_yards"} -> {20, 90}
      {"TE", "receiving_td"} -> {0, 2}
      {_, "fumble_lost"} -> {0, 1}
      _ -> {0, 0}
    end
  end

  defp range("mlb", pos, cat) when pos in ["SP", "RP"] do
    case {pos, cat} do
      {"SP", "inning_pitched"} -> {4, 7}
      {"RP", "inning_pitched"} -> {1, 2}
      {"SP", "strikeout_pitched"} -> {3, 10}
      {"RP", "strikeout_pitched"} -> {0, 3}
      {_, "win"} -> {0, 1}
      {_, "earned_run"} -> {0, 4}
      _ -> {0, 0}
    end
  end

  defp range("mlb", _pos, cat) do
    case cat do
      "single" -> {0, 3}
      "double" -> {0, 2}
      "triple" -> {0, 1}
      "home_run" -> {0, 2}
      "rbi" -> {0, 4}
      "run" -> {0, 3}
      "walk" -> {0, 2}
      "stolen_base" -> {0, 2}
      _ -> {0, 0}
    end
  end

  defp range(_sport, _pos, _cat), do: {0, 0}

  # Pick a range by NBA/WNBA position tier: guard / forward / center.
  defp tier(pos, guard, forward, center) do
    cond do
      pos in ["PG", "SG", "G"] -> guard
      pos in ["SF", "PF", "F"] -> forward
      pos == "C" -> center
      true -> guard
    end
  end
end
