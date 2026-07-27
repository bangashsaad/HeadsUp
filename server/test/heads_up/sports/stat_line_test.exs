defmodule HeadsUp.Sports.StatLineTest do
  use ExUnit.Case, async: true

  alias HeadsUp.Sports.StatLine

  test "basketball line shows non-zero categories in order with abbreviations" do
    line = %{"point" => 21, "rebound" => 8, "assist" => 5, "steal" => 0, "block" => 1, "turnover" => 2, "three_made" => 3}
    assert StatLine.format("wnba", line) == "21 PTS · 8 REB · 5 AST · 1 BLK · 3 3PM · 2 TO"
  end

  test "baseball pitcher line formats innings and skips zeros" do
    line = %{"inning_pitched" => 6.0, "strikeout_pitched" => 7, "earned_run" => 2, "win" => 1, "home_run" => 0, "rbi" => 0}
    assert StatLine.format("mlb", line) == "6.0 IP · 7 K · 2 ER · 1 W"
  end

  test "an all-zero line is blank (yet to play)" do
    assert StatLine.format("wnba", %{"point" => 0, "rebound" => 0}) == ""
  end
end
