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
end
