defmodule HeadsUpWeb.UserJSON do
  alias HeadsUp.Accounts.User

  @doc "Auth response: the login token plus the user."
  def auth(%{user: user, token: token} = assigns) do
    %{token: token, user: data(user, assigns[:coins])}
  end

  @doc "Just the user."
  def user(%{user: user} = assigns) do
    %{user: data(user, assigns[:coins])}
  end

  @doc "The public shape of a user (never includes the password)."
  def data(%User{} = user, coins \\ nil) do
    base = %{
      id: user.id,
      username: user.username,
      email: user.email,
      email_verified: not is_nil(user.email_verified_at),
      inserted_at: user.inserted_at
    }

    if is_integer(coins), do: Map.put(base, :coins, coins), else: base
  end
end
