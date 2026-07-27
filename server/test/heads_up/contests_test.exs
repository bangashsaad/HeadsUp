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

  describe "group duels (3-4 players)" do
    setup %{a: a} do
      c = user("c")
      d = user("d")
      Repo.insert!(%Friendship{requester_id: a.id, addressee_id: c.id, status: "accepted"})
      Repo.insert!(%Friendship{requester_id: a.id, addressee_id: d.id, status: "accepted"})
      %{c: c, d: d}
    end

    test "creating a group duel seats host + invitees, no opponent_id", %{a: a, b: b, c: c} do
      duel = group(a, [b, c])

      assert duel.status == "pending"
      assert duel.opponent_id == nil

      assert [host, s1, s2] = Contests.list_participants(duel.id)
      assert host.user_id == a.id and host.seat == 0 and host.status == "accepted"
      assert s1.user_id == b.id and s1.status == "invited"
      assert s2.user_id == c.id and s2.status == "invited"
    end

    test "invitees only need to be friends with the host", %{a: a, b: b, c: c} do
      # b and c aren't friends with each other — only with a. Still fine.
      assert %Duel{} = group(a, [b, c])
    end

    test "a non-friend invitee is rejected", %{a: a, b: b} do
      stranger = user("x")

      assert {:error, "you can only challenge your friends"} =
               Contests.create_challenge(a, %{
                 "opponent_ids" => [b.id, stranger.id],
                 "sport" => "wnba",
                 "draft_starts_at" => future_iso()
               })
    end

    test "the duel flips accepted once every seat is in", %{a: a, b: b, c: c} do
      duel = group(a, [b, c])

      {:ok, after_first} = Contests.accept_challenge(b, duel.id)
      assert after_first.status == "pending"

      {:ok, after_second} = Contests.accept_challenge(c, duel.id)
      assert after_second.status == "accepted"
      assert Enum.all?(Contests.list_participants(duel.id), &(&1.status == "accepted"))
    end

    test "a decline shrinks the match and the rest can still fill it", %{a: a, b: b, c: c, d: d} do
      duel = group(a, [b, c, d])

      {:ok, still} = Contests.decline_challenge(d, duel.id)
      assert still.status == "pending"

      {:ok, _} = Contests.accept_challenge(b, duel.id)
      {:ok, done} = Contests.accept_challenge(c, duel.id)
      assert done.status == "accepted"
    end

    test "a decline that resolves the last open seat also flips accepted", %{a: a, b: b, c: c} do
      duel = group(a, [b, c])

      {:ok, _} = Contests.accept_challenge(b, duel.id)
      {:ok, done} = Contests.decline_challenge(c, duel.id)

      assert done.status == "accepted"
    end

    test "declines collapsing below 2 players cancel the duel", %{a: a, b: b, c: c} do
      duel = group(a, [b, c])

      {:ok, _} = Contests.decline_challenge(b, duel.id)
      {:ok, dead} = Contests.decline_challenge(c, duel.id)

      assert dead.status == "cancelled"
    end

    test "host force-start drops pending invitees and starts with the group", %{a: a, b: b, c: c} do
      duel = group(a, [b, c])
      {:ok, _} = Contests.accept_challenge(b, duel.id)

      {:ok, started} = Contests.start_with_group(a, duel.id)

      assert started.status == "accepted"
      statuses = Map.new(Contests.list_participants(duel.id), &{&1.user_id, &1.status})
      assert statuses[b.id] == "accepted"
      assert statuses[c.id] == "declined"
    end

    test "force-start needs at least 2 accepted seats", %{a: a, b: b, c: c} do
      duel = group(a, [b, c])
      assert {:error, :not_enough_players} = Contests.start_with_group(a, duel.id)
    end

    test "only the host can force-start", %{a: a, b: b, c: c} do
      duel = group(a, [b, c])
      {:ok, _} = Contests.accept_challenge(b, duel.id)
      assert {:error, :not_found} = Contests.start_with_group(b, duel.id)
    end

    test "the host can't respond to a seat and outsiders get not_found", %{a: a, b: b, c: c} do
      duel = group(a, [b, c])
      assert {:error, :not_found} = Contests.accept_challenge(a, duel.id)
      assert {:error, :not_found} = Contests.accept_challenge(user("z"), duel.id)
    end

    test "counters are 1v1-only", %{a: a, b: b, c: c} do
      duel = group(a, [b, c])

      assert {:error, :not_found} =
               Contests.counter_challenge(b, duel.id, %{"sport" => "wnba", "draft_starts_at" => future_iso()})
    end

    test "members see the group duel in list/get, strangers don't", %{a: a, b: b, c: c} do
      duel = group(a, [b, c])

      assert Enum.any?(Contests.list_duels(b), &(&1.id == duel.id))
      assert %Duel{} = Contests.get_duel(c, duel.id)
      assert Contests.get_duel(user("w"), duel.id) == nil
    end

    test "player_ids lists accepted seats in seat order", %{a: a, b: b, c: c} do
      duel = group(a, [b, c])
      {:ok, _} = Contests.accept_challenge(c, duel.id)
      {:ok, _} = Contests.accept_challenge(b, duel.id)

      assert Contests.player_ids(Repo.get(Duel, duel.id)) == [a.id, b.id, c.id]
    end

    test "group rematch re-invites the accepted seats, tapper becomes host", %{a: a, b: b, c: c} do
      duel = group(a, [b, c])
      {:ok, _} = Contests.accept_challenge(b, duel.id)
      {:ok, _} = Contests.accept_challenge(c, duel.id)

      # b and c were never friends — playing together is enough for a rematch.
      {:ok, rematch} = Contests.rematch(b, duel.id)

      assert rematch.opponent_id == nil
      assert rematch.parent_duel_id == duel.id
      assert [host, s1, s2] = Contests.list_participants(rematch.id)
      assert host.user_id == b.id and host.status == "accepted"
      assert Enum.sort([s1.user_id, s2.user_id]) == Enum.sort([a.id, c.id])
      assert s1.status == "invited" and s2.status == "invited"
    end

    test "a group that shrank to 2 players rematches as a classic 1v1", %{a: a, b: b, c: c} do
      duel = group(a, [b, c])
      {:ok, _} = Contests.accept_challenge(b, duel.id)
      {:ok, _} = Contests.decline_challenge(c, duel.id)

      {:ok, rematch} = Contests.rematch(a, duel.id)

      assert rematch.opponent_id == b.id
      assert rematch.parent_duel_id == duel.id
    end

    test "a declined invitee has no group rematch to offer", %{a: a, b: b, c: c} do
      duel = group(a, [b, c])
      {:ok, _} = Contests.accept_challenge(b, duel.id)
      {:ok, _} = Contests.decline_challenge(c, duel.id)

      assert {:error, :not_found} = Contests.rematch(c, duel.id)
    end
  end

  # --- helpers ------------------------------------------------------------

  defp group(host, invitees, attrs \\ %{}) do
    {:ok, duel} =
      Contests.create_challenge(
        host,
        Map.merge(
          %{"opponent_ids" => Enum.map(invitees, & &1.id), "sport" => "wnba", "draft_starts_at" => future_iso()},
          attrs
        )
      )

    duel
  end

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
      stake_coins: 0,
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
