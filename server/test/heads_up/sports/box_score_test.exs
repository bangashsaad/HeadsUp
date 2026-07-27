defmodule HeadsUp.Sports.BoxScoreTest do
  use ExUnit.Case, async: true

  alias HeadsUp.Sports.BoxScore

  defmodule WnbaStub do
    def summary(_sport, _id) do
      {:ok,
       %{
         "header" => %{
           "id" => "999",
           "competitions" => [
             %{
               "status" => %{"type" => %{"state" => "post", "shortDetail" => "Final"}},
               "competitors" => [%{"homeAway" => "home", "score" => "85", "team" => %{"abbreviation" => "MIN"}}]
             }
           ]
         },
         "boxscore" => %{
           "players" => [
             %{
               "team" => %{"abbreviation" => "MIN", "shortDisplayName" => "Lynx"},
               "statistics" => [
                 %{
                   "labels" => ~w(MIN PTS FG 3PT FT REB AST TO STL BLK),
                   "athletes" => [
                     %{"starter" => true, "athlete" => %{"displayName" => "Natasha Howard", "position" => %{"abbreviation" => "F"}}, "stats" => ~w(36 21 9-17 0-0 3-4 14 2 0 3 1)}
                   ]
                 }
               ]
             }
           ]
         }
       }}
    end
  end

  defmodule MlbStub do
    def summary(_sport, _id) do
      {:ok,
       %{
         "header" => %{
           "id" => "777",
           "competitions" => [
             %{
               "status" => %{"type" => %{"state" => "post", "shortDetail" => "Final"}},
               "competitors" => [%{"homeAway" => "away", "score" => "4", "team" => %{"abbreviation" => "CIN"}}]
             }
           ]
         },
         "boxscore" => %{
           "players" => [
             %{
               "team" => %{"abbreviation" => "CIN", "shortDisplayName" => "Reds"},
               "statistics" => [
                 %{"type" => "batting", "labels" => ~w(H-AB AB R H RBI HR BB K), "athletes" => [
                   %{"starter" => true, "athlete" => %{"displayName" => "Elly De La Cruz", "position" => %{"abbreviation" => "SS"}}, "stats" => ~w(2-4 4 1 2 1 1 1 0)}
                 ]},
                 %{"type" => "pitching", "labels" => ~w(IP H R ER BB K HR), "athletes" => [
                   %{"starter" => true, "athlete" => %{"displayName" => "Brady Singer", "position" => %{"abbreviation" => "SP"}}, "stats" => ~w(6.0 4 2 2 1 7 1)}
                 ]}
               ]
             }
           ]
         }
       }}
    end
  end

  test "WNBA: one table with fantasy computed from the box columns" do
    assert {:ok, box} = BoxScore.for_event("wnba", "1", client: WnbaStub)
    assert box.state == "post" and box.status == "Final"

    [team] = box.teams
    assert team.abbrev == "MIN" and team.score == "85"
    [group] = team.groups
    assert group.columns == ~w(MIN PTS FG 3PT FT REB AST TO STL BLK)

    [row] = group.rows
    assert row.name == "Natasha Howard" and row.position == "F" and row.starter
    # 21 + 14*1.25 + 2*1.5 + 3*2 + 1*2 = 49.5
    assert row.fantasy == 49.5
  end

  test "MLB: batting + pitching tables, approximate live fantasy" do
    assert {:ok, box} = BoxScore.for_event("mlb", "1", client: MlbStub)
    [team] = box.teams
    assert team.abbrev == "CIN"
    assert Enum.map(team.groups, & &1.type) == ["batting", "pitching"]

    [bat] = hd(team.groups).rows
    # single 3 + HR 10 + RBI*2 + run*2 + walk*2 = 19.0
    assert bat.fantasy == 19.0

    [pit] = List.last(team.groups).rows
    # 6.0 IP * 2.25 + 7 K * 2 - 2 ER * 2 = 23.5
    assert pit.fantasy == 23.5
  end

  test "surfaces a feed error" do
    defmodule ErrStub do
      def summary(_s, _i), do: {:error, {:http, 500}}
    end

    assert {:error, {:http, 500}} = BoxScore.for_event("wnba", "1", client: ErrStub)
  end
end
