defmodule HeadsUp.Sports.ProfileTest do
  use ExUnit.Case, async: true

  alias HeadsUp.Sports.Profile
  alias HeadsUp.Sports.Player

  defmodule StubClient do
    def gamelog(_athlete_id) do
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

  defp wnba_player, do: %Player{id: 1, sport: "wnba", external_id: "3149391", name: "A'ja Wilson", team: "LV", position: "C", projection: 80.0}

  test "assembles a fantasy game log + season averages for a WNBA player" do
    assert {:ok, profile} = Profile.for_player(wnba_player(), client: StubClient)
    assert profile.available

    # newest game first
    assert [g1, g2] = profile.games
    assert g1.opponent == "CHI"
    assert g1.home_away == "vs"
    assert g1.result == "W"
    assert g1.points == 30 and g1.rebounds == 15 and g1.three_made == 1
    # 30 + 15*1.25 + 1*1.5 + 4*2 + 3*2 + 4*-0.5 + 1*0.5 = 62.75
    assert g1.fantasy == 62.8
    assert g2.fantasy == 36.5

    assert profile.season.games_played == 2
    assert profile.season.points == 24.0
    assert profile.season.fantasy == 49.6
  end

  test "a non-WNBA player (name-slug id) reports no data, no network" do
    nba = %Player{id: 2, sport: "nba", external_id: "lebron-james", name: "LeBron James", team: "LAL", position: "SF"}
    assert {:ok, %{available: false, games: []}} = Profile.for_player(nba)
  end
end
