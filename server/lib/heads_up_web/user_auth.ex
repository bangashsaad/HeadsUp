defmodule HeadsUpWeb.UserAuth do
  @moduledoc """
  Plugs for API authentication via a Bearer token in the Authorization header.
  """
  import Plug.Conn

  alias HeadsUp.Accounts

  @doc """
  Reads the `Authorization: Bearer <token>` header and, if valid, assigns
  `conn.assigns.current_user`. Does not block the request on its own.
  """
  def fetch_api_user(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         %Accounts.User{} = user <- Accounts.get_user_by_api_token(token) do
      conn
      |> assign(:current_user, user)
      |> assign(:user_token, token)
    else
      _ -> assign(conn, :current_user, nil)
    end
  end

  @doc """
  Halts with 401 unless a user was found by `fetch_api_user/2`.
  """
  @doc """
  Halts with 403 unless the current user's email is verified. Config-gated
  (`:require_verified_email`) so tests and emergencies can switch it off;
  pre-verification accounts were backfilled as verified.
  """
  def require_verified_email(conn, _opts) do
    user = conn.assigns[:current_user]

    if not Application.get_env(:heads_up, :require_verified_email, true) or
         (user && user.email_verified_at) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> Phoenix.Controller.json(%{error: "Verify your email to duel — check your inbox for the code"})
      |> halt()
    end
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> Phoenix.Controller.put_view(json: HeadsUpWeb.ErrorJSON)
      |> Phoenix.Controller.render(:"401")
      |> halt()
    end
  end
end
