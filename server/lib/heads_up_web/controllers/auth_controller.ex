defmodule HeadsUpWeb.AuthController do
  use HeadsUpWeb, :controller

  alias HeadsUp.Accounts
  alias HeadsUp.Coins

  plug :put_view, json: HeadsUpWeb.UserJSON
  action_fallback HeadsUpWeb.FallbackController

  # POST /api/register  { "username", "email", "password" }
  def register(conn, params) do
    with {:ok, user} <- Accounts.register_user(params) do
      # Idempotency-keyed, and the comeback bonus heals a miss — never fail a
      # fresh registration over its welcome coins.
      _ = Coins.grant_signup(user.id)
      token = Accounts.create_user_api_token(user)

      conn
      |> put_status(:created)
      |> render(:auth, user: user, token: token, coins: Coins.balance(user.id))
    end
  end

  # POST /api/login  { "email", "password" }
  def login(conn, %{"email" => email, "password" => password}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      token = Accounts.create_user_api_token(user)
      render(conn, :auth, user: user, token: token, coins: Coins.balance(user.id))
    else
      {:error, "Invalid email or password"}
    end
  end

  def login(_conn, _params), do: {:error, "Email and password are required"}

  # DELETE /api/logout  (requires auth)
  def logout(conn, _params) do
    Accounts.delete_user_api_token(conn.assigns.user_token)
    send_resp(conn, :no_content, "")
  end

  # GET /api/me  (requires auth)
  def me(conn, _params) do
    user = conn.assigns.current_user
    # The lazy faucet: a busted wallet gets its daily comeback bonus on the
    # next app open — no cron needed.
    _ = Coins.maybe_comeback(user.id)
    render(conn, :user, user: user, coins: Coins.balance(user.id))
  end

  # PUT /api/me/password  { "current_password", "password" }  (requires auth)
  def change_password(conn, %{"current_password" => current, "password" => new}) do
    case Accounts.update_user_password(conn.assigns.current_user, current, %{"password" => new}) do
      {:ok, _user} -> send_resp(conn, :no_content, "")
      {:error, :invalid_current_password} -> {:error, "Current password is incorrect"}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  def change_password(_conn, _params), do: {:error, "current_password and password are required"}

  # PUT /api/me/push_token  { "push_token": "ExponentPushToken[...]" | null }
  def push_token(conn, params) do
    case Accounts.update_push_token(conn.assigns.current_user, params["push_token"]) do
      {:ok, _user} -> send_resp(conn, :no_content, "")
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end
end
