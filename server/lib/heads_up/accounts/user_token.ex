defmodule HeadsUp.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  @rand_size 32

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
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc "Query for a specific token row (used when logging out)."
  def by_token_and_context_query(token, context) do
    from HeadsUp.Accounts.UserToken, where: [token: ^token, context: ^context]
  end

  @doc "All tokens belonging to a user."
  def by_user_and_contexts_query(user, :all) do
    from t in HeadsUp.Accounts.UserToken, where: t.user_id == ^user.id
  end
end
