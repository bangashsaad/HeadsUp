defmodule HeadsUp.FriendGroupsTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.{Accounts, Repo, Social}
  alias HeadsUp.Social.Friendship

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  defp befriend(a, b), do: Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})

  setup do
    owner = user("owner")
    f1 = user("pal1")
    f2 = user("pal2")
    befriend(owner, f1)
    befriend(f2, owner)
    %{owner: owner, f1: f1, f2: f2}
  end

  test "create, list, rename, delete", %{owner: owner} do
    assert {:ok, group} = Social.create_friend_group(owner, "  crew  ")
    # Names are trimmed + whitespace-collapsed so near-duplicates can't split.
    assert group.name == "crew"

    assert [%{id: id, name: "crew", member_ids: []}] = Social.list_friend_groups(owner)
    assert id == group.id

    assert {:ok, _} = Social.rename_friend_group(owner, group.id, "work")
    assert [%{name: "work"}] = Social.list_friend_groups(owner)

    assert {:ok, _} = Social.delete_friend_group(owner, group.id)
    assert Social.list_friend_groups(owner) == []
  end

  test "duplicate names are rejected per owner, but two owners may share one", %{owner: owner, f1: f1} do
    assert {:ok, _} = Social.create_friend_group(owner, "crew")
    assert {:error, changeset} = Social.create_friend_group(owner, "crew")
    assert "you already have a group with that name" in errors_on(changeset).owner_id

    assert {:ok, _} = Social.create_friend_group(f1, "crew")
  end

  test "membership is replaced wholesale and limited to real friends", %{owner: owner, f1: f1, f2: f2} do
    stranger = user("stranger")
    {:ok, group} = Social.create_friend_group(owner, "crew")

    assert {:ok, %{member_ids: ids}} =
             Social.set_friend_group_members(owner, group.id, [f1.id, f2.id, stranger.id])

    # The stranger is silently dropped — a stale client can't smuggle them in.
    assert Enum.sort(ids) == Enum.sort([f1.id, f2.id])

    assert {:ok, %{member_ids: [only]}} = Social.set_friend_group_members(owner, group.id, [f2.id])
    assert only == f2.id
    assert [%{member_ids: [^only]}] = Social.list_friend_groups(owner)
  end

  test "another user's group is invisible and untouchable", %{owner: owner, f1: f1} do
    {:ok, mine} = Social.create_friend_group(owner, "private")

    assert Social.list_friend_groups(f1) == []
    assert {:error, :not_found} = Social.rename_friend_group(f1, mine.id, "stolen")
    assert {:error, :not_found} = Social.delete_friend_group(f1, mine.id)
    assert {:error, :not_found} = Social.set_friend_group_members(f1, mine.id, [])
  end

  test "deleting the owner's account takes their groups with it", %{owner: owner} do
    {:ok, _} = Social.create_friend_group(owner, "crew")
    {:ok, _} = Accounts.delete_account(owner, "password123")

    assert Social.list_friend_groups(owner) == []
  end
end
