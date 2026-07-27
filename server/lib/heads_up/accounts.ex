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

  # --- email verification + password reset (6-digit codes) ------------------

  @doc "Sends (or re-sends) the email-verification code. Replaces any prior code."
  def deliver_email_verification(%User{} = user) do
    code = issue_code(user, "verify_email")

    send_code_email(
      user.email,
      "Your verification code",
      "Your verification code is #{code}. It expires in 15 minutes.\n\nEnter it in the app to unlock challenges."
    )
  end

  @doc "Confirms the account's email with a live code. `{:ok, user}` or `{:error, :invalid_code}`."
  def verify_email(%User{} = user, code) when is_binary(code) do
    case Repo.one(UserToken.verify_email_code_query(user.id, code, "verify_email")) do
      nil ->
        {:error, :invalid_code}

      _token ->
        Repo.delete_all(UserToken.by_user_and_context_query(user, "verify_email"))

        user
        |> Ecto.Changeset.change(email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second))
        |> Repo.update()
    end
  end

  @doc """
  Sends a password-reset code IF the email belongs to a live account. Always
  returns `:ok` — the response never reveals whether an email exists.
  """
  def deliver_password_reset(email) when is_binary(email) do
    case Repo.get_by(User, email: email) do
      %User{deleted_at: nil} = user ->
        code = issue_code(user, "reset_password")

        send_code_email(
          user.email,
          "Your password reset code",
          "Your password reset code is #{code}. It expires in 15 minutes.\n\nIf you didn't ask for this, ignore it — your password is unchanged."
        )

      _ ->
        :ok
    end
  end

  @doc """
  Resets the password with a live emailed code, kills every login session,
  and (since the inbox was just proven) marks the email verified. Returns
  `{:ok, user}`, `{:error, :invalid_code}`, or `{:error, changeset}`.
  """
  def reset_password(email, code, new_password) when is_binary(email) do
    with %User{deleted_at: nil} = user <- Repo.get_by(User, email: email),
         %UserToken{} <- Repo.one(UserToken.verify_email_code_query(user.id, code, "reset_password")),
         {:ok, fresh} <- user |> User.password_changeset(%{"password" => new_password}) |> Repo.update() do
      Repo.delete_all(UserToken.by_user_and_contexts_query(user, :all))

      fresh
      |> Ecto.Changeset.change(email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update()
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      _ -> {:error, :invalid_code}
    end
  end

  defp issue_code(user, context) do
    Repo.delete_all(UserToken.by_user_and_context_query(user, context))
    {code, token} = UserToken.build_email_code(user, context)
    Repo.insert!(token)
    code
  end

  defp send_code_email(to, subject, body) do
    sender = Application.get_env(:heads_up, :mail_from, {"HeadsUp", "onboarding@resend.dev"})

    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(to)
      |> Swoosh.Email.from(sender)
      |> Swoosh.Email.subject(subject)
      |> Swoosh.Email.text_body(body)

    case HeadsUp.Mailer.deliver(email) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.warning("mail delivery failed: #{inspect(reason)}")
        :ok
    end
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
