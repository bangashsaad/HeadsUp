defmodule HeadsUp.Sports.SeedsNflTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.Repo
  alias HeadsUp.Sports.{Player, Seeds}

  # Same stub shape as the WNBA seed test: canned responses out of the process
  # dictionary, since the seeder runs in-process.
  defmodule SeedStub do
    def teams(_sport), do: Process.get(:teams_resp, {:error, :unset})
    def roster(_sport, id), do: Process.get({:roster_resp, id}, {:error, :unset})
  end

  @teams_ok {:ok,
             %{
               "sports" => [
                 %{"leagues" => [%{"teams" => [%{"team" => %{"id" => "1", "abbreviation" => "KC"}}]}]}
               ]
             }}

  # The real NFL feed groups athletes by unit and includes three groups of
  # people who cannot play: IR, suspended, and the practice squad.
  @roster_ok {:ok,
              %{
                "team" => %{"abbreviation" => "KC"},
                "athletes" => [
                  %{
                    "position" => "offense",
                    "items" => [
                      %{"id" => "3139477", "displayName" => "Patrick Mahomes", "position" => %{"abbreviation" => "QB"}},
                      %{"id" => "4241457", "displayName" => "Isiah Pacheco", "position" => %{"abbreviation" => "RB"}},
                      %{"id" => "15847", "displayName" => "Travis Kelce", "position" => %{"abbreviation" => "TE"}},
                      %{"id" => "4362628", "displayName" => "Xavier Worthy", "position" => %{"abbreviation" => "WR"}},
                      %{"id" => "2977644", "displayName" => "Creed Humphrey", "position" => %{"abbreviation" => "C"}},
                      %{"id" => "3051880", "displayName" => "Jawaan Taylor", "position" => %{"abbreviation" => "OT"}}
                    ]
                  },
                  %{
                    "position" => "defense",
                    "items" => [
                      %{"id" => "3122123", "displayName" => "Chris Jones", "position" => %{"abbreviation" => "DT"}},
                      %{"id" => "4243331", "displayName" => "Trent McDuffie", "position" => %{"abbreviation" => "CB"}},
                      %{"id" => "4361307", "displayName" => "Nick Bolton", "position" => %{"abbreviation" => "LB"}}
                    ]
                  },
                  %{"position" => "specialTeam", "items" => [%{"id" => "2971573", "displayName" => "Harrison Butker", "position" => %{"abbreviation" => "PK"}}]},
                  %{"position" => "injuredReserveOrOut", "items" => [%{"id" => "111", "displayName" => "Hurt Guy", "position" => %{"abbreviation" => "WR"}}]},
                  %{"position" => "suspended", "items" => [%{"id" => "222", "displayName" => "Banned Guy", "position" => %{"abbreviation" => "RB"}}]},
                  %{"position" => "practiceSquad", "items" => [%{"id" => "333", "displayName" => "Scout Teamer", "position" => %{"abbreviation" => "QB"}}]}
                ]
              }}

  defp athlete(id, name, pos),
    do: %{"id" => id, "displayName" => name, "position" => %{"abbreviation" => pos}}

  setup do
    Process.put(:teams_resp, @teams_ok)
    Process.put({:roster_resp, "1"}, @roster_ok)
    :ok
  end

  defp seeded do
    Repo.all(from(p in Player, where: p.sport == "nfl", select: {p.name, p.position}))
  end

  test "keeps only the positions the NFL scoring chart can reward" do
    assert {:ok, %{inserted: 4}} = Seeds.run_from_espn("nfl", client: SeedStub)

    names = seeded() |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    assert names == ["Isiah Pacheco", "Patrick Mahomes", "Travis Kelce", "Xavier Worthy"]
  end

  test "drops linemen, defenders and kickers rather than seeding unscoreable rows" do
    assert {:ok, _} = Seeds.run_from_espn("nfl", client: SeedStub)

    dropped = ["Creed Humphrey", "Jawaan Taylor", "Chris Jones", "Trent McDuffie", "Nick Bolton", "Harrison Butker"]
    seeded_names = Enum.map(seeded(), &elem(&1, 0))

    for name <- dropped, do: refute name in seeded_names
  end

  test "skips injured-reserve, suspended and practice-squad groups" do
    assert {:ok, _} = Seeds.run_from_espn("nfl", client: SeedStub)

    seeded_names = Enum.map(seeded(), &elem(&1, 0))

    # All three are QB/RB/WR, so only the group filter keeps them out.
    refute "Hurt Guy" in seeded_names
    refute "Banned Guy" in seeded_names
    refute "Scout Teamer" in seeded_names
  end

  test "normalizes fullbacks and halfbacks to RB without swallowing defenders" do
    roster =
      {:ok,
       %{
         "team" => %{"abbreviation" => "KC"},
         "athletes" => [
           athlete("1", "Full Back", "FB"),
           athlete("2", "Half Back", "HB"),
           athlete("3", "Corner Man", "Cornerback"),
           athlete("4", "Backer Man", "Linebacker"),
           athlete("5", "Slot Guy", "Wide Receiver")
         ]
       }}

    Process.put({:roster_resp, "1"}, roster)
    assert {:ok, _} = Seeds.run_from_espn("nfl", client: SeedStub)

    assert Enum.sort(seeded()) == [{"Full Back", "RB"}, {"Half Back", "RB"}, {"Slot Guy", "WR"}]
  end
end
