defmodule HeadsUp.DraftsTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.{Accounts, Drafts, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Drafts.{AutoPick, Lineup}
  alias HeadsUp.Sports.Player

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{
        "username" => name,
        "email" => "#{name}@example.com",
        "password" => "password123"
      })

    u
  end

  defp accepted_duel(challenger, opponent) do
    future = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

    Repo.insert!(%Duel{
      challenger_id: challenger.id,
      opponent_id: opponent.id,
      sport: "wnba",
      draft_type: "snake",
      lineup_template: "wnba_standard",
      roster_size: 5,
      pick_clock_seconds: 60,
      scoring_rules: %{},
      wager_cents: 0,
      draft_starts_at: future,
      status: "accepted"
    })
  end

  describe "coin_flip/3 (injectable rng)" do
    test "is deterministic under a stubbed rng" do
      assert Drafts.coin_flip(10, 20, fn 2 -> 1 end) == 10
      assert Drafts.coin_flip(10, 20, fn 2 -> 2 end) == 20
    end
  end

  describe "build_pick_order/3 + picker_for/2 (2-player snake)" do
    test "snakes correctly and is off-by-one safe" do
      order = Drafts.build_pick_order(1, 2, 3)
      assert order == [1, 2, 2, 1, 1, 2]
      assert length(order) == 6
      assert Drafts.picker_for(order, 1) == 1
      assert Drafts.picker_for(order, 2) == 2
      assert Drafts.picker_for(order, 3) == 2
      assert Drafts.picker_for(order, 4) == 1
    end
  end

  describe "get_or_create_draft_for_duel/1" do
    test "creates one lobby draft with total_picks = 2 * slot_count, idempotently" do
      duel = accepted_duel(user("alice"), user("bob"))

      assert {:ok, draft} = Drafts.get_or_create_draft_for_duel(duel)
      assert draft.status == "lobby"
      # wnba_standard = 5 slots -> 10 total picks
      assert draft.total_picks == 10

      assert {:ok, again} = Drafts.get_or_create_draft_for_duel(duel)
      assert again.id == draft.id
    end
  end

  describe "start_active/2" do
    test "records the coin-flip winner and flips the duel to drafting" do
      challenger = user("carol")
      opponent = user("dave")
      duel = accepted_duel(challenger, opponent)
      {:ok, draft} = Drafts.get_or_create_draft_for_duel(duel)

      assert {:ok, active} = Drafts.start_active(draft, challenger.id)
      assert active.status == "active"
      assert active.first_picker_id == challenger.id
      assert active.current_pick_number == 1
      assert Repo.get(Duel, duel.id).status == "drafting"
    end
  end

  describe "record_pick/1 + replay/1" do
    test "persists picks, advances the pointer, and replays in order" do
      challenger = user("erin")
      opponent = user("frank")
      duel = accepted_duel(challenger, opponent)
      {:ok, draft} = Drafts.get_or_create_draft_for_duel(duel)
      [p1, p2] = wnba_players(2)

      assert {:ok, _} =
               Drafts.record_pick(%{
                 draft_id: draft.id,
                 pick_number: 1,
                 user_id: challenger.id,
                 player_id: p1.id,
                 slot: "PG1",
                 auto_picked: false
               })

      assert Repo.get(HeadsUp.Drafts.Draft, draft.id).current_pick_number == 2

      assert {:ok, _} =
               Drafts.record_pick(%{
                 draft_id: draft.id,
                 pick_number: 2,
                 user_id: opponent.id,
                 player_id: p2.id,
                 slot: "PG1",
                 auto_picked: true
               })

      replay = Drafts.replay(draft.id)
      assert Enum.map(replay, & &1.pick_number) == [1, 2]
      assert Enum.map(replay, & &1.player_id) == [p1.id, p2.id]
      assert [%{auto_picked: false}, %{auto_picked: true}] = replay
    end

    test "shared board: the same player can't be drafted twice" do
      duel = accepted_duel(user("gina"), user("hank"))
      {:ok, draft} = Drafts.get_or_create_draft_for_duel(duel)
      [p1] = wnba_players(1)
      base = %{draft_id: draft.id, user_id: duel.challenger_id, slot: "PG1", auto_picked: false}

      assert {:ok, _} = Drafts.record_pick(Map.merge(base, %{pick_number: 1, player_id: p1.id}))

      assert {:error, %Ecto.Changeset{}} =
               Drafts.record_pick(Map.merge(base, %{pick_number: 2, player_id: p1.id}))
    end
  end

  describe "draft_pool/1" do
    test "returns a sport's players keyed by id, with projection" do
      [p1, _p2] = wnba_players(2)
      pool = Drafts.draft_pool("wnba")
      assert is_map(pool)
      assert pool[p1.id].projection == p1.projection
      assert pool[p1.id].position == p1.position
    end
  end

  describe "AutoPick.pick/3 (rank-first + position-aware)" do
    @slots Lineup.slots("nba_standard")

    test "takes the highest-projection player that fits an open slot" do
      available = [
        %{id: 1, position: "PG", projection: 99.0},
        %{id: 2, position: "SG", projection: 90.0}
      ]

      assert AutoPick.pick(available, [], @slots) == {:ok, 1, "PG1"}
    end

    test "defers to the next-best when the top player's slot is filled" do
      available = [
        %{id: 1, position: "PG", projection: 99.0},
        %{id: 2, position: "SG", projection: 90.0}
      ]

      # PG1 already filled -> the 99-rated PG can't fit, take the SG
      assert AutoPick.pick(available, ["PG1"], @slots) == {:ok, 2, "SG1"}
    end

    test "returns :error when no available player fits any open slot" do
      available = [%{id: 1, position: "PG", projection: 99.0}]
      assert AutoPick.pick(available, ["PG1"], @slots) == :error
    end
  end

  # Insert N real wnba players (projection descending) into the test DB.
  defp wnba_players(n) do
    positions = ~w(PG SG SF PF C)

    for i <- 1..n do
      Repo.insert!(%Player{
        sport: "wnba",
        external_id: "test-wnba-#{i}",
        name: "Test Player #{i}",
        team: "TST",
        position: Enum.at(positions, rem(i - 1, 5)),
        projection: 100.0 - i
      })
    end
  end
end
