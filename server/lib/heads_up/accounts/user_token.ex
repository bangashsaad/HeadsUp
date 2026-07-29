defmodule HeadsUp.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  @rand_size 32
  # A login token is good for 60 days of real use; `touch`ed on every
  # authenticated request, so an active phone never gets logged out while a
  # stolen or abandoned token dies on its own.
  @api_token_validity_days 60

  schema "users_tokens" do
    field :token, :binary
    field :context, :string

    belongs_to :user, HeadsUp.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a random API token for a user. Returns `{encoded_token, struct}`:
  the encoded string is sent to the phone; the struct is saved to the database.
  """
  def build_api_token(user) do
    raw = :crypto.strong_rand_bytes(@rand_size)
    encoded = Base.url_encode64(raw, padding: false)
    {encoded, %__MODULE__{token: raw, context: "api", user_id: user.id}}
  end

  @doc """
  Query to fetch the user that owns a given (encoded) API token.
  """
  def verify_api_token_query(encoded_token) do
    case Base.url_decode64(encoded_token, padding: false) do
      {:ok, raw} ->
        query =
          from token in by_token_and_context_query(raw, "api"),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^@api_token_validity_days, "day"),
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc "Slides an active token's expiry forward (called at most daily)."
  def refresh_api_token_query(encoded_token) do
    case Base.url_decode64(encoded_token, padding: false) do
      {:ok, raw} -> {:ok, by_token_and_context_query(raw, "api")}
      :error -> :error
    end
  end

  @doc "Tokens past their validity window — swept so the table can't grow forever."
  def expired_api_tokens_query do
    from t in __MODULE__,
      where: t.context == "api" and t.inserted_at <= ago(^@api_token_validity_days, "day")
  end

  def api_token_validity_days, do: @api_token_validity_days

  @code_validity_minutes 15

  @doc """
  A 6-digit email code (verification / password reset), stored HASHED. Phones
  type codes; codes don't need deep links. Returns `{code, struct}`.
  """
  def build_email_code(user, context) when context in ["verify_email", "reset_password"] do
    code = Enum.random(100_000..999_999) |> Integer.to_string()
    {code, %__MODULE__{token: hash_code(code), context: context, user_id: user.id}}
  end

  @doc "Query matching a live (unexpired) email code for the user + context."
  def verify_email_code_query(user_id, code, context) when is_binary(code) do
    from t in __MODULE__,
      where:
        t.user_id == ^user_id and t.context == ^context and t.token == ^hash_code(code) and
          t.inserted_at > ago(^@code_validity_minutes, "minute")
  end

  @doc "All of a user's codes for one context (cleared on resend / success)."
  def by_user_and_context_query(user, context) when is_binary(context) do
    from t in __MODULE__, where: t.user_id == ^user.id and t.context == ^context
  end

  defp hash_code(code), do: :crypto.hash(:sha256, code)

  @doc "Query for a specific token row (used when logging out)."
  def by_token_and_context_query(token, context) do
    from HeadsUp.Accounts.UserToken, where: [token: ^token, context: ^context]
  end

  @doc "All tokens belonging to a user."
  def by_user_and_contexts_query(user, :all) do
    from t in HeadsUp.Accounts.UserToken, where: t.user_id == ^user.id
  end
end
