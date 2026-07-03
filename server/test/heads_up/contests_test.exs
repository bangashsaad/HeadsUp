defmodule HeadsUp.ContestsTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.{Accounts, Contests, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Social.Friendship

  setup do
    a = user("a")
    b = user("b")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
    %{a: a, b: b}
  end

  describe "rematch/3" do
    test "clones terms into a fresh pending challenge to the same opponent", %{a: a, b: b} do
      duel = settled(a, b)

      assert {:ok, rematch} = Contests.rematch(a, duel.id)
      assert rematch.status == "pending"
      assert rematch.challenger_id == a.id and rematch.opponent_id == b.id
      assert rematch.sport == duel.sport
      assert rematch.lineup_template == duel.lineup_template
      assert rematch.pick_clock_seconds == duel.pick_clock_seconds
      assert rematch.scoring_rules == duel.scoring_rules
      assert rematch.parent_duel_id == duel.id
      assert rematch.draft_starts_at != nil
    end

    test "the opponent can rematch too — challenger flips to them", %{a: a, b: b} do
      duel = settled(a, b)
      assert {:ok, rematch} = Contests.rematch(b, duel.id)
      assert rematch.challenger_id == b.id and rematch.opponent_id == a.id
    end

    test "a stranger's duel is not found", %{a: a, b: b} do
      c = user("c")
      duel = settled(a, b)
      assert {:error, :not_found} = Contests.rematch(c, duel.id)
    end
  end

  describe "participant seats (multiplayer shadow model)" do
    test "creating a challenge seeds host + invitee seats", %{a: a, b: b} do
      duel = challenge(a, b)
      [host, invitee] = Contests.list_participants(duel.id)

      assert host.seat == 0 and host.user_id == a.id and host.status == "accepted"
      assert invitee.seat == 1 and invitee.user_id == b.id and invitee.status == "invited"
    end

    test "accepting marks the invitee's seat accepted", %{a: a, b: b} do
      duel = challenge(a, b)
      {:ok, _} = Contests.accept_challenge(b, duel.id)

      assert [%{seat: 0, status: "accepted"}, %{seat: 1, status: "accepted"}] =
               Contests.list_participants(duel.id)
    end

    test "declining marks the invitee's seat declined", %{a: a, b: b} do
      duel = challenge(a, b)
      {:ok, _} = Contests.decline_challenge(b, duel.id)

      assert [_host, invitee] = Contests.list_participants(duel.id)
      assert invitee.user_id == b.id and invitee.status == "declined"
    end

    test "cancelling leaves seats untouched", %{a: a, b: b} do
      duel = challenge(a, b)
      {:ok, _} = Contests.cancel_challenge(a, duel.id)

      assert [%{status: "accepted"}, %{status: "invited"}] = Contests.list_participants(duel.id)
    end

    test "a counter seeds fresh seats with roles swapped", %{a: a, b: b} do
      duel = challenge(a, b)

      {:ok, counter} =
        Contests.counter_challenge(b, duel.id, %{"sport" => "wnba", "draft_starts_at" => future_iso()})

      [host, invitee] = Contests.list_participants(counter.id)
      assert host.seat == 0 and host.user_id == b.id and host.status == "accepted"
      assert invitee.seat == 1 and invitee.user_id == a.id and invitee.status == "invited"
    end

    test "rematch seeds seats on the new duel", %{a: a, b: b} do
      duel = settled(a, b)
      {:ok, rematch} = Contests.rematch(b, duel.id)

      [host, invitee] = Contests.list_participants(rematch.id)
      assert host.user_id == b.id and invitee.user_id == a.id
    end
  end

  # --- helpers ------------------------------------------------------------

  defp challenge(challenger, opponent, attrs \\ %{}) do
    {:ok, duel} =
      Contests.create_challenge(
        challenger,
        Map.merge(%{"opponent_id" => opponent.id, "sport" => "wnba", "draft_starts_at" => future_iso()}, attrs)
      )

    duel
  end

  defp future_iso do
    DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
  end

  defp settled(c, o) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%Duel{
      challenger_id: c.id,
      opponent_id: o.id,
      sport: "wnba",
      draft_type: "snake",
      lineup_template: "wnba_standard",
      roster_size: 5,
      pick_clock_seconds: 90,
      scoring_rules: %{"point" => 1, "rebound" => 1.25},
      wager_cents: 0,
      draft_starts_at: now,
      status: "settled",
      winner_id: c.id,
      settled_at: now
    })
  end

  defp user(name) do
    {:ok, u} = Accounts.register_user(%{"username" => "usr#{name}", "email" => "#{name}@example.com", "password" => "password123"})
    u
  end
end
