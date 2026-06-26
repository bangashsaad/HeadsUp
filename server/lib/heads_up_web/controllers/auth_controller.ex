defmodule HeadsUpWeb.AuthController do
  use HeadsUpWeb, :controller

  alias HeadsUp.Accounts

  plug :put_view, json: HeadsUpWeb.UserJSON
  action_fallback HeadsUpWeb.FallbackController

  # POST /api/register  { "username", "email", "password" }
  def register(conn, params) do
    with {:ok, user} <- Accounts.register_user(params) do
      token = Accounts.create_user_api_token(user)

      conn
      |> put_status(:created)
      |> render(:auth, user: user, token: token)
    end
  end

  # POST /api/login  { "email", "password" }
  def login(conn, %{"email" => email, "password" => password}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      token = Accounts.create_user_api_token(user)
      render(conn, :auth, user: user, token: token)
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
    render(conn, :user, user: conn.assigns.current_user)
  end
end
