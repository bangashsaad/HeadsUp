defmodule HeadsUp.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :email, :string
    # `virtual: true` means it lives only in memory while we validate/hash it —
    # the plain password is never saved to the database.
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    # Expo push token for this user's device (one device per user for the beta).
    field :push_token, :string, redact: true
    # Set when the account is deleted (anonymized): blocks login, hides from
    # search. The row survives so opponents' history and the ledger stay whole.
    field :deleted_at, :utc_datetime

    has_many :tokens, HeadsUp.Accounts.UserToken

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for registering a new user: validates the fields, then hashes
  the password into `hashed_password`.
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :password])
    |> validate_username()
    |> validate_email()
    |> validate_password()
    |> hash_password()
  end

  defp validate_username(changeset) do
    changeset
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 20)
    |> validate_format(:username, ~r/^[a-zA-Z0-9_]+$/,
      message: "can only contain letters, numbers, and underscores"
    )
    |> unsafe_validate_unique(:username, HeadsUp.Repo)
    |> unique_constraint(:username)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, HeadsUp.Repo)
    |> unique_constraint(:email)
  end

  @doc "Changeset for setting/clearing the device push token."
  def push_token_changeset(user, attrs) do
    user
    |> cast(attrs, [:push_token])
    |> validate_length(:push_token, max: 200)
  end

  @doc """
  Changeset for changing the password (the caller verifies the CURRENT password
  first). Validates and re-hashes the new password.
  """
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_password()
    |> hash_password()
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
  end

  defp hash_password(changeset) do
    case changeset do
      %{valid?: true, changes: %{password: password}} ->
        changeset
        |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
        |> delete_change(:password)

      _ ->
        changeset
    end
  end

  @doc """
  Verifies a plaintext password against the stored hash. Runs a dummy check
  when there's no user, so attackers can't tell which emails exist by timing.
  """
  def valid_password?(%HeadsUp.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
