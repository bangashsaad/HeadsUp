defmodule HeadsUp.BlockingTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.{Accounts, Contests, Repo, Social}
  alias HeadsUp.Social.Friendship

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  defp befriend(a, b), do: Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
  defp future, do: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()

  setup do
    a = user("ann")
    b = user("bob")
    %{a: a, b: b}
  end

  test "blocking severs the friendship and empties the groups", %{a: a, b: b} do
    befriend(a, b)
    {:ok, group} = Social.create_friend_group(a, "crew")
    {:ok, _} = Social.set_friend_group_members(a, group.id, [b.id])

    assert {:ok, _} = Social.block_user(a, b.id)

    assert Social.list_friends(a) == []
    assert Social.list_friends(b) == []
    assert [%{member_ids: []}] = Social.list_friend_groups(a)
  end

  test "the block hides both ways in search", %{a: a, b: b} do
    {:ok, _} = Social.block_user(a, b.id)

    assert Social.search_users("bob", a) == []
    # And the blocked user can't find the blocker either.
    assert Social.search_users("ann", b) == []
  end

  test "neither side can send a friend request, and the error doesn't leak", %{a: a, b: b} do
    {:ok, _} = Social.block_user(a, b.id)

    assert {:error, msg} = Social.send_friend_request(b, a.id)
    # Must NOT reveal that they were blocked.
    refute msg =~ "block"
    assert {:error, _} = Social.send_friend_request(a, b.id)
  end

  test "a blocked pair can't challenge each other", %{a: a, b: b} do
    befriend(a, b)
    {:ok, _} = Social.block_user(a, b.id)

    assert {:error, _} =
             Contests.create_challenge(b, %{"opponent_id" => a.id, "sport" => "wnba", "draft_starts_at" => future()})
  end

  test "blocking cancels a shared live duel and refunds both stakes", %{a: a, b: b} do
    befriend(a, b)
    {:ok, _} = HeadsUp.Coins.grant_signup(a.id)
    {:ok, _} = HeadsUp.Coins.grant_signup(b.id)
    a_before = HeadsUp.Coins.balance(a.id)
    b_before = HeadsUp.Coins.balance(b.id)

    {:ok, duel} =
      Contests.create_challenge(a, %{
        "opponent_id" => b.id,
        "sport" => "wnba",
        "stake_coins" => 100,
        "draft_starts_at" => future()
      })

    {:ok, _} = Contests.accept_challenge(b, duel.id)
    assert HeadsUp.Coins.balance(a.id) == a_before - 100

    {:ok, _} = Social.block_user(a, b.id)

    # You can't be left sitting in a draft room with someone you blocked.
    assert Repo.get(HeadsUp.Contests.Duel, duel.id).status == "cancelled"
    assert HeadsUp.Coins.balance(a.id) == a_before
    assert HeadsUp.Coins.balance(b.id) == b_before
  end

  test "blocking leaves settled history alone", %{a: a, b: b} do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    duel =
      Repo.insert!(%HeadsUp.Contests.Duel{
        challenger_id: a.id,
        opponent_id: b.id,
        sport: "wnba",
        draft_type: "snake",
        lineup_template: "wnba_5",
        roster_size: 5,
        pick_clock_seconds: 30,
        scoring_rules: %{},
        stake_coins: 0,
        draft_starts_at: now,
        status: "settled",
        winner_id: a.id,
        settled_at: now
      })

    {:ok, _} = Social.block_user(a, b.id)
    assert Repo.get(HeadsUp.Contests.Duel, duel.id).status == "settled"
  end

  test "unblocking lifts the wall but does not restore the friendship", %{a: a, b: b} do
    befriend(a, b)
    {:ok, _} = Social.block_user(a, b.id)
    assert :ok = Social.unblock_user(a, b.id)

    refute Social.blocked?(a, b.id)
    assert Social.list_friends(a) == []
    # They can find each other again and re-add.
    assert [%{user: found}] = Social.search_users("bob", a)
    assert found.id == b.id
  end

  test "blocking is idempotent, self-blocking is refused, and the list reads back", %{a: a, b: b} do
    assert {:ok, _} = Social.block_user(a, b.id)
    assert {:ok, _} = Social.block_user(a, b.id)
    assert [only] = Social.list_blocked(a)
    assert only.id == b.id

    assert {:error, changeset} = Social.block_user(a, a.id)
    assert "you can't block yourself" in errors_on(changeset).blocked_id
  end

  test "a block makes the profile unreachable by id, both ways", %{a: a, b: b} do
    befriend(a, b)
    assert {:ok, _} = Social.public_profile(b, a.id)

    {:ok, _} = Social.block_user(a, b.id)

    assert {:error, :not_found} = Social.public_profile(b, a.id)
    assert {:error, :not_found} = Social.public_profile(a, b.id)
  end

  test "a group rematch drops a seat that has since been blocked", %{a: a, b: b} do
    c = user("cat")
    befriend(a, b)
    befriend(a, c)
    befriend(b, c)

    {:ok, duel} =
      Contests.create_challenge(a, %{
        "opponent_ids" => [b.id, c.id],
        "sport" => "wnba",
        "roster_size" => 5,
        "draft_starts_at" => future()
      })

    {:ok, _} = Contests.accept_challenge(b, duel.id)
    {:ok, _} = Contests.accept_challenge(c, duel.id)

    # Everyone played; then c blocks the host. A rematch must not re-invite c.
    {:ok, _} = Social.block_user(c, a.id)

    assert {:ok, rematch} = Contests.rematch(a, duel.id)
    assert rematch.opponent_id == b.id
    refute Enum.any?(Repo.all(HeadsUp.Contests.Participant), &(&1.duel_id == rematch.id and &1.user_id == c.id))
  end
end
