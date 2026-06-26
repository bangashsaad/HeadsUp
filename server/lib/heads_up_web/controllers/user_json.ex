defmodule HeadsUpWeb.UserJSON do
  alias HeadsUp.Accounts.User

  @doc "Auth response: the login token plus the user."
  def auth(%{user: user, token: token}) do
    %{token: token, user: data(user)}
  end

  @doc "Just the user."
  def user(%{user: user}) do
    %{user: data(user)}
  end

  @doc "The public shape of a user (never includes the password)."
  def data(%User{} = user) do
    %{
      id: user.id,
      username: user.username,
      email: user.email,
      inserted_at: user.inserted_at
    }
  end
end
