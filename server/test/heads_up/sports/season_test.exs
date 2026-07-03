defmodule HeadsUp.Sports.SeasonTest do
  # async: false — one test swaps the app-env season client for the backstop.
  use HeadsUp.DataCase, async: false

  alias HeadsUp.{Accounts, Contests, Repo}
  alias HeadsUp.Social.Friendship
  alias HeadsUp.Sports.{Player, Season}

  defmodule LiveStub do
    def scoreboard(_sport, _range),
      do: {:ok, %{"events" => [%{"date" => "2026-07-05T23:00Z"}, %{"date" => "2026-07-04T23:00Z"}]}}
  end

  defmodule EmptyStub do
    def scoreboard(_sport, _range), do: {:ok, %{"events" => []}}
  end

  defmodule DownStub do
    def scoreboard(_sport, _range), do: {:error, :timeout}
  end

  test "games in the window + a real pool = playable (earliest game surfaced)" do
    seed_pool("wnba", 30)

    s = Season.status("wnba", client: LiveStub, cache: false)
    assert s.playable and s.pool_ready
    assert s.next_game_at == "2026-07-04T23:00Z"
  end

  test "an empty window is off-season even with a real pool" do
    seed_pool("wnba", 30)

    refute Season.status("wnba", client: EmptyStub, cache: false).playable
    refute Season.in_season?("wnba", client: EmptyStub, cache: false)
  end

  test "a feed error fails open for the backstop, but a placeholder pool still gates the UI" do
    s = Season.status("nba", client: DownStub, cache: false)
    refute s.playable
    refute s.pool_ready
    assert Season.in_season?("nba", client: DownStub, cache: false)
  end

  test "challenge creation is blocked when ESPN positively says: no games" do
    a = user("sza")
    b = user("szb")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})

    Application.put_env(:heads_up, :season_client, EmptyStub)

    on_exit(fn ->
      Application.delete_env(:heads_up, :season_client)
      :persistent_term.erase({HeadsUp.Sports.Season, "nba"})
    end)

    future = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_iso8601()

    assert {:error, msg} =
             Contests.create_challenge(a, %{"opponent_id" => b.id, "sport" => "nba", "draft_starts_at" => future})

    assert msg =~ "no games"
  end

  defp seed_pool(sport, n) do
    for i <- 1..n do
      Repo.insert!(%Player{
        sport: sport,
        external_id: "#{900_000 + i}",
        name: "Pool Player #{i}",
        team: "TST",
        position: "G",
        projection: 10.0
      })
    end
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => "usr#{name}", "email" => "#{name}@example.com", "password" => "password123"})

    u
  end
end
