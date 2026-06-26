defmodule HeadsUp.Contests.Scoring do
  @moduledoc """
  Default fantasy scoring charts per sport (industry-standard-ish). These are
  the values a challenge ships with; the challenger can override them in the
  terms, and whatever is agreed gets frozen onto the duel.
  """

  @nfl %{
    "passing_yards" => 0.04,
    "passing_td" => 4,
    "interception" => -2,
    "rushing_yards" => 0.1,
    "rushing_td" => 6,
    "reception" => 1,
    "receiving_yards" => 0.1,
    "receiving_td" => 6,
    "fumble_lost" => -2
  }

  @nba %{
    "point" => 1,
    "rebound" => 1.25,
    "assist" => 1.5,
    "steal" => 2,
    "block" => 2,
    "turnover" => -0.5,
    "three_made" => 0.5
  }

  @mlb %{
    "single" => 3,
    "double" => 5,
    "triple" => 8,
    "home_run" => 10,
    "rbi" => 2,
    "run" => 2,
    "walk" => 2,
    "stolen_base" => 5,
    "inning_pitched" => 2.25,
    "strikeout_pitched" => 2,
    "win" => 4,
    "earned_run" => -2
  }

  def default_rules("nfl"), do: @nfl
  def default_rules("nba"), do: @nba
  def default_rules("mlb"), do: @mlb
  def default_rules(_), do: %{}
end
