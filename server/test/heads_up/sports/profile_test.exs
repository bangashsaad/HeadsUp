defmodule HeadsUp.Sports.ProfileTest do
  use ExUnit.Case, async: true

  alias HeadsUp.Sports.Profile
  alias HeadsUp.Sports.Player

  # WNBA gamelog (reads by column LABEL).
  defmodule WnbaStub do
    def gamelog("wnba", _athlete_id) do
      {:ok,
       %{
         "labels" => ~w(MIN PTS REB AST STL BLK TO FG FG% 3PT 3P% FT FT% PF),
         "events" => %{
           "401" => %{"gameDate" => "2026-06-28T23:00Z", "atVs" => "vs", "gameResult" => "W", "opponent" => %{"abbreviation" => "CHI"}},
           "402" => %{"gameDate" => "2026-06-26T23:00Z", "atVs" => "@", "gameResult" => "L", "opponent" => %{"abbreviation" => "NY"}}
         },
         "seasonTypes" => [
           %{
             "categories" => [
               %{
                 "events" => [
                   %{"eventId" => "401", "stats" => ~w(34 30 15 1 4 3 4 8-14 57.1 1-3 33.3 13-16 81.3 2)},
                   %{"eventId" => "402", "stats" => ~w(30 18 6 8 0 0 3 6-12 50.0 1-2 50.0 5-6 83.3 1)}
                 ]
               }
             ]
           }
         ]
       }}
    end
  end

  # MLB batting gamelog (reads by stable machine `names`).
  defmodule MlbStub do
    def gamelog("mlb", _athlete_id) do
      {:ok,
       %{
         "names" => ~w(atBats runs hits doubles triples homeRuns RBIs walks hitByPitch strikeouts stolenBases caughtStealing avg onBasePct slugAvg OPS),
         "events" => %{
           "501" => %{"gameDate" => "2026-06-28T17:00Z", "atVs" => "vs", "gameResult" => "W", "opponent" => %{"abbreviation" => "NYY"}},
           "502" => %{"gameDate" => "2026-06-26T17:00Z", "atVs" => "@", "gameResult" => "L", "opponent" => %{"abbreviation" => "BOS"}}
         },
         "seasonTypes" => [
           %{
             "categories" => [
               %{
                 "events" => [
                   %{"eventId" => "501", "stats" => ~w(4 1 2 1 0 1 3 1 0 1 1 0 .300 .380 .550 .930)},
                   %{"eventId" => "502", "stats" => ~w(3 0 1 0 0 0 0 0 0 2 0 0 .280 .350 .480 .830)}
                 ]
               }
             ]
           }
         ]
       }}
    end
  end

  defp wnba_player, do: %Player{id: 1, sport: "wnba", external_id: "3149391", name: "A'ja Wilson", team: "LV", position: "C", projection: 80.0}
  defp mlb_player, do: %Player{id: 3, sport: "mlb", external_id: "33333", name: "Aaron Judge", team: "NYY", position: "OF", projection: 50.0}

  test "WNBA: fantasy game log + season tiles (basketball)" do
    assert {:ok, profile} = Profile.for_player(wnba_player(), client: WnbaStub)
    assert profile.available

    # newest game first
    assert [g1, g2] = profile.games
    assert g1.opponent == "CHI" and g1.home_away == "vs" and g1.result == "W"
    # 30 + 15*1.25 + 1*1.5 + 4*2 + 3*2 + 4*-0.5 + 1*0.5 = 62.75
    assert g1.fantasy == 62.8
    assert g1.line == "30 PTS · 15 REB · 1 AST"
    assert g2.fantasy == 36.5

    assert profile.season.games_played == 2
    assert profile.season.fantasy == 49.6
    assert profile.season.tiles == [
             %{label: "PPG", value: "24.0"},
             %{label: "RPG", value: "10.5"},
             %{label: "APG", value: "4.5"},
             %{label: "FPG", value: "49.6"}
           ]
  end

  test "MLB: batting game log + season tiles (baseball)" do
    assert {:ok, profile} = Profile.for_player(mlb_player(), client: MlbStub)
    assert profile.available

    assert [g1, g2] = profile.games
    assert g1.opponent == "NYY" and g1.result == "W"
    # double 5 + HR 10 + 3 RBI*2 + run 2 + walk 2 + SB 5 = 30.0
    assert g1.fantasy == 30.0
    assert g1.line == "2-4 · 1 HR · 3 RBI · 1 SB · 1 BB"
    assert g2.fantasy == 3.0
    assert g2.line == "1-3"

    assert profile.season.games_played == 2
    assert profile.season.fantasy == 16.5
    # 3 hits / 7 at-bats = .429
    assert profile.season.tiles == [
             %{label: "AVG", value: ".429"},
             %{label: "HR", value: "1"},
             %{label: "RBI", value: "3"},
             %{label: "FPG", value: "16.5"}
           ]
  end

  test "a player with a name-slug id reports no data, no network" do
    nba = %Player{id: 2, sport: "nba", external_id: "lebron-james", name: "LeBron James", team: "LAL", position: "SF"}
    assert {:ok, %{available: false, games: []}} = Profile.for_player(nba)
  end
end
