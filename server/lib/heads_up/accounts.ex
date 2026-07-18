defmodule HeadsUp.Accounts do
  @moduledoc """
  The Accounts context: registering users, logging in, and login tokens.
  """

  import Ecto.Query, warn: false
  alias HeadsUp.Repo
  alias HeadsUp.Accounts.{User, UserToken}

  @doc "Registers a new user from the given attrs."
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Fetches a user by id (returns nil if not found)."
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Returns the user if the email + password match, otherwise nil.
  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password) and is_nil(user.deleted_at), do: user
  end

  @doc """
  Changes a user's password after verifying their CURRENT password. Returns
  `{:ok, user}`, `{:error, :invalid_current_password}`, or `{:error, changeset}`.
  """
  def update_user_password(%User{} = user, current_password, attrs) do
    if User.valid_password?(user, current_password) do
      user
      |> User.password_changeset(attrs)
      |> Repo.update()
    else
      {:error, :invalid_current_password}
    end
  end

  @doc "Stores (or clears, with nil) the user's device push token."
  def update_push_token(%User{} = user, push_token) do
    user
    |> User.push_token_changeset(%{push_token: push_token})
    |> Repo.update()
  end

  @doc "Creates and stores an API token for the user, returning the encoded string."
  def create_user_api_token(user) do
    {encoded, user_token} = UserToken.build_api_token(user)
    Repo.insert!(user_token)
    encoded
  end

  @doc "Returns the user for an API token, or nil if the token is invalid."
  def get_user_by_api_token(encoded_token) when is_binary(encoded_token) do
    case UserToken.verify_api_token_query(encoded_token) do
      # Ghost accounts have no valid tokens (all deleted at scrub time) — the
      # deleted_at check is the belt for any token caught mid-flight.
      {:ok, query} ->
        case Repo.one(query) do
          %User{deleted_at: nil} = user -> user
          _ -> nil
        end

      :error ->
        nil
    end
  end

  def get_user_by_api_token(_), do: nil

  @doc "Deletes a single API token (logout)."
  def delete_user_api_token(encoded_token) do
    with {:ok, raw} <- Base.url_decode64(encoded_token, padding: false) do
      Repo.delete_all(UserToken.by_token_and_context_query(raw, "api"))
    end

    :ok
  end

  @doc """
  Deletes an account, Apple-style: verify the CURRENT password, then
  anonymize-and-scrub rather than hard-delete — cascades would erase
  opponents' shared duel history and tear the double-entry coin ledger.

  What happens: their live duels are evacuated (cancelled, every escrowed
  stake refunded — settled and in-play "drafted" duels are left to history/
  settlement), friendships are removed both ways, every login token dies,
  and the row is scrubbed to a ghost (`deleted_123`, dead email, random
  password hash, no push token, `deleted_at` stamped).

  Returns `{:ok, ghost}` or `{:error, :invalid_current_password}`.
  """
  def delete_account(%User{} = user, current_password) do
    if User.valid_password?(user, current_password) do
      {:ok, do_delete_account(user)}
    else
      {:error, :invalid_current_password}
    end
  end

  defp do_delete_account(%User{} = user) do
    # Leave/cancel live duels AS the user (refund paths need the actor),
    # before their identity is scrubbed.
    HeadsUp.Contests.evacuate_user(user)
    HeadsUp.Social.delete_all_friendships(user)
    Repo.delete_all(UserToken.by_user_and_contexts_query(user, :all))

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    user
    |> Ecto.Changeset.change(%{
      username: "deleted_#{user.id}",
      email: "deleted+#{user.id}@deleted.invalid",
      hashed_password: Bcrypt.hash_pwd_salt(:crypto.strong_rand_bytes(24) |> Base.encode64()),
      push_token: nil,
      deleted_at: now
    })
    |> Repo.update!()
  end
end
