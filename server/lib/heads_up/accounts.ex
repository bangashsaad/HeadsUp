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
    if User.valid_password?(user, password), do: user
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
      {:ok, query} -> Repo.one(query)
      :error -> nil
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
end
