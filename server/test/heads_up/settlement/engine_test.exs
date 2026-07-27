defmodule HeadsUp.Settlement.EngineTest do
  use ExUnit.Case, async: true

  alias HeadsUp.Contests.{Duel, Scoring}
  alias HeadsUp.Settlement.Engine

  @rules Scoring.default_rules("wnba")

  describe "player_points/2" do
    test "sums stat_line[cat] * rules[cat] over the chart" do
      # point 1, rebound 1.25, assist 1.5, steal 2, block 2, turnover -0.5, three_made 0.5
      line = %{"point" => 20, "rebound" => 8, "assist" => 4, "three_made" => 2}
      # 20 + 10 + 6 + 1 = 37.0
      assert Engine.player_points(line, @rules) == 37.0
    end

    test "missing categories and an empty/nil line score 0" do
      assert Engine.player_points(%{}, @rules) == 0.0
      assert Engine.player_points(nil, @rules) == 0.0
      assert Engine.player_points(%{"point" => 10}, @rules) == 10.0
    end

    test "negative-weight categories subtract" do
      line = %{"point" => 10, "turnover" => 4}
      # 10 + (4 * -0.5) = 8.0
      assert Engine.player_points(line, @rules) == 8.0
    end
  end

  describe "score_roster/4" do
    test "orders by pick_number and rounds points + total to 2dp" do
      picks = [
        %{user_id: 1, player_id: 20, pick_number: 3, slot: "SF1"},
        %{user_id: 1, player_id: 10, pick_number: 1, slot: "PG1"}
      ]

      stats = %{10 => %{"point" => 25}, 20 => %{"point" => 11}}
      result = Engine.score_roster(1, picks, stats, @rules)

      assert Enum.map(result.players, & &1.player_id) == [10, 20]
      assert result.total == 36.0
    end

    test "a drafted player absent from stats scores 0 (draft risk)" do
      picks = [%{user_id: 1, player_id: 99, pick_number: 1, slot: "PG1"}]
      result = Engine.score_roster(1, picks, %{}, @rules)
      assert [%{points: points, stat_line: stat_line}] = result.players
      assert points == 0.0
      assert stat_line == %{}
      assert result.total == 0.0
    end
  end

  describe "settle/3" do
    defp duel, do: %Duel{challenger_id: 1, opponent_id: 2, scoring_rules: @rules}

    defp picks do
      [
        %{user_id: 1, player_id: 10, pick_number: 1, slot: "PG1"},
        %{user_id: 2, player_id: 20, pick_number: 2, slot: "PG1"}
      ]
    end

    test "declares the higher total the winner" do
      stats = %{10 => %{"point" => 30}, 20 => %{"point" => 10}}
      result = Engine.settle(duel(), picks(), stats)

      assert result.result == :win
      assert result.winner_id == 1
      assert result.challenger.total == 30.0
      assert result.opponent.total == 10.0
    end

    test "equal rounded totals is a tie (winner_id nil)" do
      stats = %{10 => %{"point" => 15}, 20 => %{"point" => 15}}
      result = Engine.settle(duel(), picks(), stats)

      assert result.result == :tie
      assert result.winner_id == nil
    end

    test "float dust does not split a true tie" do
      # 0.04 * 3 categories of 1 each could accumulate float noise; rounding to 2dp ties
      rules = %{"a" => 0.1, "b" => 0.2}
      d = %Duel{challenger_id: 1, opponent_id: 2, scoring_rules: rules}
      stats = %{10 => %{"a" => 1, "b" => 1}, 20 => %{"a" => 1, "b" => 1}}
      result = Engine.settle(d, picks(), stats)
      assert result.result == :tie
    end
  end
end
