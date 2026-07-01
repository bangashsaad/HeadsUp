defmodule HeadsUp.Sports.SeedsWnbaTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.Repo
  alias HeadsUp.Sports.{Player, Seeds}

  # A stub implementing the Client API (teams/0, roster/1), reading canned
  # responses from the test process dictionary (the seeder runs in-process).
  defmodule SeedStub do
    def teams(_sport), do: Process.get(:teams_resp, {:error, :unset})
    def roster(_sport, id), do: Process.get({:roster_resp, id}, {:error, :unset})
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

  test "MLB seed keeps granular positions (SP/OF) and uses the mlb default projection" do
    Process.put(:teams_resp, @teams_ok)

    Process.put(
      {:roster_resp, "1"},
      {:ok,
       %{
         "team" => %{"abbreviation" => "NYY"},
         "athletes" => [
           %{"id" => "33333", "displayName" => "Aaron Judge", "position" => %{"abbreviation" => "RF"}},
           %{"id" => "44444", "displayName" => "Gerrit Cole", "position" => %{"abbreviation" => "SP"}}
         ]
       }}
    )

    assert {:ok, %{inserted: 2}} = Seeds.run_from_espn("mlb", client: SeedStub)

    judge = Repo.get_by(Player, external_id: "33333")
    cole = Repo.get_by(Player, external_id: "44444")
    assert judge.sport == "mlb" and judge.position == "OF" and judge.projection == 5.0
    assert cole.position == "SP"
  end

  test "prune_legacy drops non-numeric placeholder rows but keeps real ESPN + drafted ones" do
    legacy = Repo.insert!(%Player{sport: "mlb", external_id: "aaron-judge", name: "Aaron Judge", team: "NYY", position: "OF", projection: 80.0})
    real = Repo.insert!(%Player{sport: "mlb", external_id: "33333", name: "Aaron Judge", team: "NYY", position: "OF", projection: 14.0})
    other_sport = Repo.insert!(%Player{sport: "wnba", external_id: "caitlin-clark", name: "Caitlin Clark", team: "IND", position: "G", projection: 50.0})

    assert 1 = Seeds.prune_legacy("mlb")

    refute Repo.get(Player, legacy.id)
    assert Repo.get(Player, real.id)
    # other sports are untouched
    assert Repo.get(Player, other_sport.id)
  end

  test "refresh_projections overwrites projection with season FPPG for numeric ids only" do
    defmodule ProjStub do
      # "33333" has games; "99999" has an empty (no-data) log → floored to 0.0.
      def gamelog(_sport, "99999"), do: {:ok, %{"labels" => nil, "events" => %{}, "seasonTypes" => []}}

      def gamelog(_sport, _id) do
        {:ok,
         %{
           "names" => ~w(atBats runs hits doubles triples homeRuns RBIs walks hitByPitch strikeouts stolenBases),
           "events" => %{
             "501" => %{"gameDate" => "2026-06-28T17:00Z"},
             "502" => %{"gameDate" => "2026-06-26T17:00Z"}
           },
           "seasonTypes" => [
             %{"categories" => [%{"events" => [
               %{"eventId" => "501", "stats" => ~w(4 1 2 1 0 1 3 1 0 1 1)},
               %{"eventId" => "502", "stats" => ~w(3 0 1 0 0 0 0 0 0 2 0)}
             ]}]}
           ]
         }}
      end
    end

    real = Repo.insert!(%Player{sport: "mlb", external_id: "33333", name: "Aaron Judge", team: "NYY", position: "OF", projection: 5.0})
    empty = Repo.insert!(%Player{sport: "mlb", external_id: "99999", name: "No Games", team: "NYY", position: "SP", projection: 90.0})
    slug = Repo.insert!(%Player{sport: "mlb", external_id: "gerrit-cole", name: "Gerrit Cole", team: "NYY", position: "SP", projection: 5.0})

    assert {:ok, %{updated: 2, total: 2}} = Seeds.refresh_projections("mlb", client: ProjStub)

    # (30.0 + 3.0) / 2 = 16.5
    assert Repo.get(Player, real.id).projection == 16.5
    # no games → floored to 0.0 (was a stale 90.0)
    assert Repo.get(Player, empty.id).projection == 0.0
    # non-numeric id is skipped entirely
    assert Repo.get(Player, slug.id).projection == 5.0
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
