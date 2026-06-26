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
  alias HeadsUp.Social.Friendship

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

      users =
        from(u in User,
          where: u.id != ^current_user.id and ilike(u.username, ^pattern),
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

  @doc "True if the two users are accepted friends."
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
