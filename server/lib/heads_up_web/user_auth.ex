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
