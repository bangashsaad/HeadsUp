defmodule HeadsUpWeb.UserAuth do
  @moduledoc """
  Authentication for both front doors.

  The phone sends `Authorization: Bearer <token>`; the browser carries the same
  kind of token in a signed, http-only session cookie. Deliberately ONE token
  store rather than a parallel session table: expiry, the sliding refresh, the
  janitor's pruning and "log out everywhere" already work, and they keep working
  for the web without being written twice. A cookie is just a different way to
  carry the token, not a different way to be logged in.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  alias HeadsUp.Accounts

  @session_key :user_token

  @doc """
  Reads the `Authorization: Bearer <token>` header and, if valid, assigns
  `conn.assigns.current_user`. Does not block the request on its own.
  """
  def fetch_api_user(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         %Accounts.User{} = user <- Accounts.get_user_by_api_token(token) do
      Accounts.refresh_api_token(token)

      conn
      |> assign(:current_user, Accounts.touch_last_seen(user))
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

  # --- browser session ------------------------------------------------------

  @doc """
  Logs a browser in: mints a token, renews the session (so a pre-login session
  can't be fixated), and stores the token in the cookie.
  """
  def log_in_web_user(conn, %Accounts.User{} = user) do
    token = Accounts.create_user_api_token(user)

    conn
    |> renew_session()
    |> put_session(@session_key, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  @doc "Logs a browser out, revoking the token so the cookie is worthless."
  def log_out_web_user(conn) do
    if token = get_session(conn, @session_key), do: Accounts.delete_user_api_token(token)

    conn
    |> renew_session()
    |> redirect(to: "/")
  end

  @doc "Assigns `current_user` from the session cookie. Never blocks."
  def fetch_web_user(conn, _opts) do
    with token when is_binary(token) <- get_session(conn, @session_key),
         %Accounts.User{} = user <- Accounts.get_user_by_api_token(token) do
      Accounts.refresh_api_token(token)

      conn
      |> assign(:current_user, Accounts.touch_last_seen(user))
      |> assign(:user_token, token)
    else
      _ -> conn |> assign(:current_user, nil) |> assign(:user_token, nil)
    end
  end

  @doc "Sends a logged-out browser to the sign-in page, remembering where it was headed."
  def require_web_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> Phoenix.Controller.put_flash(:error, "Sign in to keep going.")
      |> put_session(:return_to, current_path(conn))
      |> redirect(to: "/login")
      |> halt()
    end
  end

  @doc "Keeps a signed-in browser off the sign-in and sign-up pages."
  def redirect_if_web_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn |> redirect(to: "/app") |> halt()
    else
      conn
    end
  end

  @doc "Where to send someone after signing in — back where they were headed."
  def return_path(conn), do: get_session(conn, :return_to) || "/app"

  # --- LiveView -------------------------------------------------------------

  @doc """
  `on_mount` hook. A LiveView re-establishes identity over the socket, where
  there is no conn — the session token is the only thing that crosses.
  """
  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, assign_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = assign_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "Sign in to keep going.")
       |> Phoenix.LiveView.redirect(to: "/login")}
    end
  end

  defp assign_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      with token when is_binary(token) <- session["user_token"] do
        Accounts.get_user_by_api_token(token)
      else
        _ -> nil
      end
    end)
  end

  # A fresh session on every login/logout, so nothing from before survives.
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp current_path(conn) do
    case conn.query_string do
      "" -> conn.request_path
      qs -> conn.request_path <> "?" <> qs
    end
  end
end
