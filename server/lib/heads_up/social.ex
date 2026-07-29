defmodule HeadsUp.Social do
  @moduledoc """
  The Social context: searching for people, friend requests, and friends.

  A friendship has a direction (requester -> addressee) and a status
  ("pending" until accepted, then "accepted"). There is at most one row per
  pair of users, in either direction.
  """

  import Ecto.Query, warn: false
  alias HeadsUp.Repo
  alias HeadsUp.Accounts.User
  alias HeadsUp.Social.{Block, Friendship, FriendGroup, FriendGroupMember}

  @doc """
  Searches users by username (case-insensitive, partial match), excluding the
  current user. Each result is tagged with the relationship to the current user.
  """
  def search_users(query, %User{} = current_user, limit \\ 20) do
    trimmed = String.trim(query || "")

    # Require at least 2 characters to avoid flooding results.
    if String.length(trimmed) < 2 do
      []
    else
      # Prefix match ("starts with") — more precise than match-anywhere, and
      # it can use a database index, so it stays fast as the user base grows.
      pattern = escape_like(trimmed) <> "%"

      hidden = blocked_ids(current_user.id)

      users =
        from(u in User,
          where:
            u.id != ^current_user.id and ilike(u.username, ^pattern) and is_nil(u.deleted_at) and
              u.id not in ^hidden,
          # Exact matches first (citext makes this case-insensitive), then A–Z.
          order_by: [desc: fragment("? = ?", u.username, ^trimmed), asc: u.username],
          limit: ^limit
        )
        |> Repo.all()

      relationships = relationship_map(current_user.id, Enum.map(users, & &1.id))

      Enum.map(users, fn user ->
        {status, friendship_id} = Map.get(relationships, user.id, {"none", nil})
        %{user: user, relationship: status, friendship_id: friendship_id}
      end)
    end
  end

  @doc "Sends a friend request from `current_user` to the user with `addressee_id`."
  def send_friend_request(%User{} = current_user, addressee_id) do
    cond do
      to_string(addressee_id) == to_string(current_user.id) ->
        {:error, "you can't friend yourself"}

      Repo.get(User, addressee_id) == nil ->
        {:error, :not_found}

      blocked?(current_user, addressee_id) ->
        {:error, "that request can't be sent"}

      existing = get_friendship_between(current_user.id, addressee_id) ->
        case existing.status do
          "accepted" -> {:error, "you're already friends"}
          _ -> {:error, "a friend request already exists"}
        end

      true ->
        %Friendship{}
        |> Friendship.changeset(%{
          requester_id: current_user.id,
          addressee_id: addressee_id,
          status: "pending"
        })
        |> Repo.insert()
        |> case do
          {:ok, friendship} ->
            HeadsUp.Notifications.notify_user(
              friendship.addressee_id,
              "Friend request 👋",
              "#{current_user.username} wants to duel you on HeadsUp",
              %{type: "friends"}
            )

            {:ok, friendship}

          error ->
            error
        end
    end
  end

  @doc "Accepts a pending request. Only the addressee can accept."
  def accept_friend_request(%User{} = current_user, friendship_id) do
    case Repo.get(Friendship, friendship_id) do
      %Friendship{addressee_id: aid, status: "pending"} = friendship
      when aid == current_user.id ->
        friendship
        |> Friendship.changeset(%{status: "accepted"})
        |> Repo.update()

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Deletes a friendship row. Used to decline an incoming request, cancel an
  outgoing one, or unfriend. Either party may do it.
  """
  def delete_friendship(%User{} = current_user, friendship_id) do
    case Repo.get(Friendship, friendship_id) do
      %Friendship{requester_id: rid, addressee_id: aid} = friendship
      when rid == current_user.id or aid == current_user.id ->
        Repo.delete(friendship)
        :ok

      _ ->
        {:error, :not_found}
    end
  end

  @doc "Lists the current user's accepted friends (as User structs)."
  def list_friends(%User{id: id}) do
    from(f in Friendship,
      where: f.status == "accepted" and (f.requester_id == ^id or f.addressee_id == ^id),
      preload: [:requester, :addressee]
    )
    |> Repo.all()
    |> Enum.map(fn f -> if f.requester_id == id, do: f.addressee, else: f.requester end)
    |> Enum.sort_by(& &1.username)
  end

  @doc "Lists pending requests sent TO the current user, with the requester preloaded."
  def list_incoming_requests(%User{id: id}) do
    from(f in Friendship,
      where: f.status == "pending" and f.addressee_id == ^id,
      order_by: [desc: f.inserted_at],
      preload: [:requester]
    )
    |> Repo.all()
  end

  @doc """
  One user's public profile from the viewer's side: the user plus the
  relationship between the two ("self" | "friends" | "request_sent" |
  "request_received" | "none") and the friendship row id if one exists.
  """
  def public_profile(%User{} = viewer, user_id) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      %User{id: id} = other when id == viewer.id ->
        {:ok, %{user: other, relationship: "self", friendship_id: nil}}

      %User{} = other ->
        {relationship, friendship_id} = viewer.id |> relationship_map([other.id]) |> Map.get(other.id, {"none", nil})
        {:ok, %{user: other, relationship: relationship, friendship_id: friendship_id}}
    end
  end

  @doc "True if the two users are accepted friends."
  def friends?(%User{} = user, other_id) when is_binary(other_id) do
    case Integer.parse(other_id) do
      {id, ""} -> friends?(user, id)
      _ -> false
    end
  end

  # --- blocking -------------------------------------------------------------

  @doc """
  Blocks a user: severs any friendship both ways, drops them from every group,
  and records the block. Effects are symmetric — neither side can search,
  friend, or challenge the other afterwards — and the blocked user is never
  notified.
  """
  def block_user(%User{id: id} = user, other_id) when is_integer(other_id) do
    # Get out of any shared draft room FIRST (stakes refunded) — a block that
    # leaves you mid-duel with the person you blocked isn't a block.
    HeadsUp.Contests.cancel_shared_live_duels(id, other_id)

    Repo.transaction(fn ->
      from(f in Friendship,
        where:
          (f.requester_id == ^id and f.addressee_id == ^other_id) or
            (f.requester_id == ^other_id and f.addressee_id == ^id)
      )
      |> Repo.delete_all()

      # Drop them from my groups, and me from theirs.
      from(m in FriendGroupMember,
        join: g in FriendGroup,
        on: g.id == m.group_id,
        where:
          (g.owner_id == ^id and m.user_id == ^other_id) or
            (g.owner_id == ^other_id and m.user_id == ^id)
      )
      |> Repo.delete_all()

      %Block{}
      |> Block.changeset(%{blocker_id: id, blocked_id: other_id})
      |> Repo.insert(on_conflict: :nothing)
      |> case do
        {:ok, _} -> :ok
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, :ok} -> {:ok, user}
      other -> other
    end
  end

  def block_user(user, other_id) when is_binary(other_id) do
    case Integer.parse(other_id) do
      {n, ""} -> block_user(user, n)
      _ -> {:error, :not_found}
    end
  end

  @doc "Lifts a block. Friendship is NOT restored — they can re-add each other."
  def unblock_user(%User{id: id}, other_id) do
    {n, _} = Repo.delete_all(from(b in Block, where: b.blocker_id == ^id and b.blocked_id == ^other_id))
    if n > 0, do: :ok, else: {:error, :not_found}
  end

  @doc "Everyone this user has blocked (public shape for the settings list)."
  def list_blocked(%User{id: id}) do
    from(b in Block, where: b.blocker_id == ^id, join: u in assoc(b, :blocked), select: u, order_by: u.username)
    |> Repo.all()
  end

  @doc "True if EITHER user has blocked the other — blocking cuts both ways."
  def blocked?(%User{id: id}, other_id) when is_integer(other_id) do
    Repo.exists?(
      from b in Block,
        where:
          (b.blocker_id == ^id and b.blocked_id == ^other_id) or
            (b.blocker_id == ^other_id and b.blocked_id == ^id)
    )
  end

  def blocked?(user, other_id) when is_binary(other_id) do
    case Integer.parse(other_id) do
      {n, ""} -> blocked?(user, n)
      _ -> false
    end
  end

  def blocked?(_, _), do: false

  # Ids in ANY block relationship with this user — excluded from search.
  defp blocked_ids(id) do
    from(b in Block,
      where: b.blocker_id == ^id or b.blocked_id == ^id,
      select: fragment("CASE WHEN ? = ? THEN ? ELSE ? END", b.blocker_id, ^id, b.blocked_id, b.blocker_id)
    )
    |> Repo.all()
  end

  # --- friend groups (private, owner-named) ---------------------------------

  @doc "The user's groups, each with its member ids, ordered by name."
  def list_friend_groups(%User{id: id}) do
    from(g in FriendGroup,
      where: g.owner_id == ^id,
      order_by: [asc: g.name],
      preload: [:members]
    )
    |> Repo.all()
    |> Enum.map(&%{id: &1.id, name: &1.name, member_ids: Enum.map(&1.members, fn m -> m.user_id end)})
  end

  @doc "Creates a group for the owner. Names are unique per owner."
  def create_friend_group(%User{id: id}, name) do
    %FriendGroup{}
    |> FriendGroup.changeset(%{name: name, owner_id: id})
    |> Repo.insert()
  end

  @doc "Renames one of the user's own groups."
  def rename_friend_group(%User{} = user, group_id, name) do
    with %FriendGroup{} = group <- owned_group(user, group_id) do
      group |> FriendGroup.changeset(%{name: name}) |> Repo.update()
    end
  end

  @doc "Deletes one of the user's own groups (membership rows cascade)."
  def delete_friend_group(%User{} = user, group_id) do
    with %FriendGroup{} = group <- owned_group(user, group_id) do
      Repo.delete(group)
    end
  end

  @doc """
  Replaces a group's membership wholesale. Only accepted friends may be
  members — anything else in `user_ids` is silently dropped, so a stale
  client can never smuggle a stranger into a group.
  """
  def set_friend_group_members(%User{} = user, group_id, user_ids) do
    with %FriendGroup{} = group <- owned_group(user, group_id) do
      friend_ids = user |> list_friends() |> MapSet.new(& &1.id)
      keep = user_ids |> List.wrap() |> Enum.uniq() |> Enum.filter(&MapSet.member?(friend_ids, &1))
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.transaction(fn ->
        Repo.delete_all(from(m in FriendGroupMember, where: m.group_id == ^group.id))

        rows = Enum.map(keep, &%{group_id: group.id, user_id: &1, inserted_at: now})
        Repo.insert_all(FriendGroupMember, rows)

        %{id: group.id, name: group.name, member_ids: keep}
      end)
    end
  end

  defp owned_group(%User{id: id}, group_id) do
    case Repo.get(FriendGroup, group_id) do
      %FriendGroup{owner_id: ^id} = group -> group
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Account-deletion scrub for groups: drops the user's own groups AND their
  membership in everyone else's. Needed because deletion anonymizes rather
  than hard-deletes the row, so the database cascade never fires — without
  this, private group names and a ghost's rows would outlive the account.
  """
  def purge_friend_groups(%User{id: id}) do
    Repo.delete_all(from(m in FriendGroupMember, where: m.user_id == ^id))
    Repo.delete_all(from(g in FriendGroup, where: g.owner_id == ^id))
    :ok
  end

  @doc "Removes every friendship (accepted or pending) involving the user — account deletion."
  def delete_all_friendships(%User{id: id}) do
    from(f in Friendship, where: f.requester_id == ^id or f.addressee_id == ^id)
    |> Repo.delete_all()

    :ok
  end

  def friends?(%User{id: id}, other_id) do
    from(f in Friendship,
      where:
        f.status == "accepted" and
          ((f.requester_id == ^id and f.addressee_id == ^other_id) or
             (f.addressee_id == ^id and f.requester_id == ^other_id))
    )
    |> Repo.exists?()
  end

  # --- helpers ---

  defp get_friendship_between(id1, id2) do
    from(f in Friendship,
      where:
        (f.requester_id == ^id1 and f.addressee_id == ^id2) or
          (f.requester_id == ^id2 and f.addressee_id == ^id1)
    )
    |> Repo.one()
  end

  # Builds %{other_user_id => {relationship_string, friendship_id}} for the
  # current user against the given list of user ids.
  defp relationship_map(_current_id, []), do: %{}

  defp relationship_map(current_id, user_ids) do
    from(f in Friendship,
      where:
        (f.requester_id == ^current_id and f.addressee_id in ^user_ids) or
          (f.addressee_id == ^current_id and f.requester_id in ^user_ids)
    )
    |> Repo.all()
    |> Map.new(fn f ->
      other_id = if f.requester_id == current_id, do: f.addressee_id, else: f.requester_id

      relationship =
        cond do
          f.status == "accepted" -> "friends"
          f.requester_id == current_id -> "request_sent"
          true -> "request_received"
        end

      {other_id, {relationship, f.id}}
    end)
  end

  # Escape LIKE/ILIKE wildcards so a username with % or _ is matched literally.
  defp escape_like(string) do
    string
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
