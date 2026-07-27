defmodule HeadsUp.Sports.StatLine do
  @moduledoc """
  Formats an engine stat-line map (the `Contests.Scoring` category keys) into a
  compact human line like `"21 PTS · 8 REB · 5 AST"` — shared by the live matchup
  view so a player's line reads the same as a box score. Only non-zero categories
  are shown, in a sport-sensible order.
  """

  @abbrev %{
    # basketball
    "point" => "PTS",
    "rebound" => "REB",
    "assist" => "AST",
    "steal" => "STL",
    "block" => "BLK",
    "three_made" => "3PM",
    "turnover" => "TO",
    # baseball
    "inning_pitched" => "IP",
    "strikeout_pitched" => "K",
    "earned_run" => "ER",
    "win" => "W",
    "home_run" => "HR",
    "rbi" => "RBI",
    "run" => "R",
    "single" => "1B",
    "double" => "2B",
    "triple" => "3B",
    "stolen_base" => "SB",
    "walk" => "BB",
    # football
    "passing_yards" => "PYD",
    "passing_td" => "PTD",
    "interception" => "INT",
    "rushing_yards" => "RYD",
    "rushing_td" => "RTD",
    "reception" => "REC",
    "receiving_yards" => "RECYD",
    "receiving_td" => "RECTD",
    "fumble_lost" => "FUM"
  }

  @order %{
    "wnba" => ~w(point rebound assist steal block three_made turnover),
    "nba" => ~w(point rebound assist steal block three_made turnover),
    "mlb" => ~w(inning_pitched strikeout_pitched earned_run win home_run rbi run single double triple stolen_base walk),
    "nfl" => ~w(passing_yards passing_td rushing_yards rushing_td reception receiving_yards receiving_td interception fumble_lost)
  }

  @doc ~s(Compact non-zero line, e.g. `"21 PTS · 8 REB"`. Empty string if nothing scored.)
  def format(sport, stat_line) when is_map(stat_line) do
    order = Map.get(@order, sport) || Map.keys(stat_line)

    order
    |> Enum.map(fn key -> {key, Map.get(stat_line, key, 0)} end)
    |> Enum.filter(fn {_k, v} -> is_number(v) and v != 0 end)
    |> Enum.map(fn {k, v} -> "#{num(v)} #{Map.get(@abbrev, k, k)}" end)
    |> Enum.join(" · ")
  end

  def format(_sport, _), do: ""

  defp num(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 1)
  defp num(v), do: to_string(v)
end
