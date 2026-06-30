defmodule HeadsUp.Sports.SeedsWnbaTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.Repo
  alias HeadsUp.Sports.{Player, Seeds}

  # A stub implementing the Client API (teams/0, roster/1), reading canned
  # responses from the test process dictionary (the seeder runs in-process).
  defmodule SeedStub do
    def teams, do: Process.get(:teams_resp, {:error, :unset})
    def roster(id), do: Process.get({:roster_resp, id}, {:error, :unset})
  end

  @teams_ok {:ok,
             %{
               "sports" => [
                 %{"leagues" => [%{"teams" => [%{"team" => %{"id" => "1", "abbreviation" => "LV"}}]}]}
               ]
             }}

  @roster_ok {:ok,
              %{
                "team" => %{"abbreviation" => "LV"},
                "athletes" => [
                  %{"id" => "3149391", "displayName" => "A'ja Wilson", "position" => %{"abbreviation" => "C"}},
                  %{"id" => "9999", "displayName" => "Rookie Newcomer", "position" => %{"abbreviation" => "F"}}
                ]
              }}

  defp seed_existing_star do
    Repo.insert!(%Player{
      sport: "wnba",
      external_id: "aja-wilson",
      name: "A'ja Wilson",
      team: "LV",
      position: "C",
      projection: 95.0
    })
  end

  defp run_ok do
    Process.put(:teams_resp, @teams_ok)
    Process.put({:roster_resp, "1"}, @roster_ok)
    Seeds.run_wnba_from_espn(client: SeedStub)
  end

  test "matches an existing star by name: preserves id + projection, migrates external_id, coarsens position" do
    star = seed_existing_star()

    assert {:ok, %{inserted: 1, updated: 1, total: 2}} = run_ok()

    reloaded = Repo.get(Player, star.id)
    assert reloaded.id == star.id
    assert reloaded.external_id == "3149391"
    assert reloaded.projection == 95.0
    assert reloaded.position == "C"
  end

  test "inserts a never-seen player at the default projection" do
    seed_existing_star()
    run_ok()

    rookie = Repo.get_by(Player, external_id: "9999")
    assert rookie.name == "Rookie Newcomer"
    assert rookie.position == "F"
    assert rookie.projection == 40.0
  end

  test "is idempotent: a second run matches by ESPN id, inserts nothing, preserves projections" do
    star = seed_existing_star()
    run_ok()
    count_after_first = Repo.aggregate(from(p in Player, where: p.sport == "wnba"), :count)

    assert {:ok, %{inserted: 0, updated: 2, total: 2}} = run_ok()
    assert Repo.aggregate(from(p in Player, where: p.sport == "wnba"), :count) == count_after_first
    assert Repo.get(Player, star.id).projection == 95.0
    assert Repo.get_by(Player, external_id: "9999").projection == 40.0
  end

  test "aborts with no writes if any roster fetch fails (transactional)" do
    star = seed_existing_star()
    Process.put(:teams_resp, @teams_ok)
    Process.put({:roster_resp, "1"}, {:error, {:http, 500}})

    assert {:error, {:roster, "1", {:http, 500}}} = Seeds.run_wnba_from_espn(client: SeedStub)

    # nothing migrated, no rows added
    assert Repo.get(Player, star.id).external_id == "aja-wilson"
    assert Repo.aggregate(from(p in Player, where: p.sport == "wnba"), :count) == 1
  end

  test "surfaces a teams fetch failure" do
    Process.put(:teams_resp, {:error, {:http, 503}})
    assert {:error, {:teams, {:http, 503}}} = Seeds.run_wnba_from_espn(client: SeedStub)
  end

  test "an ambiguous (duplicate normalized) name is never updated to the wrong player" do
    # Two existing rows that both normalize to "aja wilson".
    a = Repo.insert!(%Player{sport: "wnba", external_id: "aja-1", name: "A'ja Wilson", team: "LV", position: "C", projection: 80.0})
    b = Repo.insert!(%Player{sport: "wnba", external_id: "aja-2", name: "Aja Wilson", team: "LV", position: "C", projection: 50.0})

    Process.put(:teams_resp, @teams_ok)

    Process.put(
      {:roster_resp, "1"},
      {:ok,
       %{
         "team" => %{"abbreviation" => "LV"},
         "athletes" => [%{"id" => "3149391", "displayName" => "A'ja Wilson", "position" => %{"abbreviation" => "C"}}]
       }}
    )

    assert {:ok, %{inserted: 1, updated: 0}} = Seeds.run_wnba_from_espn(client: SeedStub)

    # Neither existing row was corrupted; the real ESPN id landed on a fresh row.
    assert Repo.get(Player, a.id).external_id == "aja-1"
    assert Repo.get(Player, b.id).external_id == "aja-2"
    assert Repo.get_by(Player, external_id: "3149391").name == "A'ja Wilson"
  end
end
