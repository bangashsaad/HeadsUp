defmodule HeadsUp.Sports.GamelogNflTest do
  use ExUnit.Case, async: true

  alias HeadsUp.Sports.Gamelog

  # ESPN varies the gamelog columns by position: a quarterback's log carries
  # passing + rushing, a skill player's carries receiving + rushing + fumbles.
  @qb_names ~w(completions passingAttempts passingYards completionPct yardsPerPassAttempt
               passingTouchdowns interceptions longPassing sacks QBRating adjQBR
               rushingAttempts rushingYards yardsPerRushAttempt rushingTouchdowns longRushing)

  @skill_names ~w(receptions receivingTargets receivingYards yardsPerReception
                  receivingTouchdowns longReception rushingAttempts rushingYards
                  yardsPerRushAttempt longRushing rushingTouchdowns fumbles
                  fumblesLost fumblesForced kicksBlocked)

  defp body(names, stats, event_id \\ "401772798") do
    %{
      "names" => names,
      "labels" => [],
      "events" => %{
        event_id => %{
          "gameDate" => "2025-12-14T18:00:00.000+00:00",
          "atVs" => "vs",
          "gameResult" => "W",
          "opponent" => %{"abbreviation" => "LAC"}
        }
      },
      "seasonTypes" => [
        %{"categories" => [%{"events" => [%{"eventId" => event_id, "stats" => stats}]}]}
      ]
    }
  end

  describe "quarterback logs" do
    test "scores passing, rushing and turnovers off the real column set" do
      # 23/34, 261 pass yds, 4 pass TD, 0 INT, 5 carries 29 rush yds, 0 rush TD.
      stats = ~w(23 34 261 67.6 7.7 4 0 42 1 130.2 88.0 5 29 5.8 0 12)

      assert [game] = Gamelog.parse("nfl", body(@qb_names, stats))

      assert game.line["passing_yards"] == 261
      assert game.line["passing_td"] == 4
      assert game.line["interception"] == 0
      assert game.line["rushing_yards"] == 29

      # 261 * 0.04 + 4 * 4 + 29 * 0.1 = 10.44 + 16 + 2.9
      assert game.fantasy == 29.3
      assert game.display == "23/34 · 261 YDS · 4 TD"
    end

    test "interceptions subtract and a rushing score is called out" do
      stats = ~w(16 28 189 57.1 6.8 0 1 26 5 62.9 56.1 2 15 7.5 1 12)

      assert [game] = Gamelog.parse("nfl", body(@qb_names, stats))

      # 189 * 0.04 - 2 + 15 * 0.1 + 6 = 7.56 - 2 + 1.5 + 6
      assert game.fantasy == 13.1
      assert game.display == "16/28 · 189 YDS · 0 TD · 1 INT · 1 RUSH TD"
    end

    test "a quarterback's missing fumble column reads as zero, not a crash" do
      stats = ~w(20 30 250 66.7 8.3 2 0 40 1 110.0 80.0 0 0 0.0 0 0)

      assert [game] = Gamelog.parse("nfl", body(@qb_names, stats))
      assert game.line["fumble_lost"] == 0
      assert game.line["reception"] == 0
    end
  end

  describe "skill-player logs" do
    test "PPR reception scoring" do
      # 5 rec, 49 yds, 1 TD, no carries, no fumbles.
      stats = ~w(5 8 49 9.8 1 22 0 0 0.0 0 0 0 0 0 0)

      assert [game] = Gamelog.parse("nfl", body(@skill_names, stats))

      # 5 * 1 + 49 * 0.1 + 6 = 5 + 4.9 + 6
      assert game.fantasy == 15.9
      assert game.display == "5 REC · 49 YDS · 1 TD"
    end

    test "a dual-threat line appends the rushing half" do
      stats = ~w(8 11 101 12.6 0 30 1 3 3.0 3 0 0 0 0 0)

      assert [game] = Gamelog.parse("nfl", body(@skill_names, stats))

      # 8 + 10.1 + 0.3
      assert game.fantasy == 18.4
      assert game.display == "8 REC · 101 YDS · 1 CAR · 3 YDS"
    end

    test "a pure runner leads with carries" do
      stats = ~w(0 0 0 0.0 0 0 18 96 5.3 24 2 0 0 0 0)

      assert [game] = Gamelog.parse("nfl", body(@skill_names, stats))

      # 96 * 0.1 + 2 * 6
      assert game.fantasy == 21.6
      assert game.display == "18 CAR · 96 YDS · 2 TD"
    end

    test "a lost fumble subtracts" do
      stats = ~w(3 5 30 10.0 0 12 0 0 0.0 0 0 1 1 0 0)

      assert [game] = Gamelog.parse("nfl", body(@skill_names, stats))

      # 3 + 3.0 - 2
      assert game.fantasy == 4.0
      assert game.line["fumble_lost"] == 1
    end

    test "a player who did nothing scores zero rather than blanking the row" do
      stats = ~w(0 0 0 0.0 0 0 0 0 0.0 0 0 0 0 0 0)

      assert [game] = Gamelog.parse("nfl", body(@skill_names, stats))
      assert game.fantasy == 0.0
      assert game.display == "0 YDS"
    end
  end

  test "football is its own stat family" do
    assert Gamelog.family("nfl") == :football
    assert Gamelog.family("mlb") == :baseball
    assert Gamelog.family("wnba") == :basketball
  end
end
