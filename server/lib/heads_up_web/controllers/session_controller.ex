defmodule HeadsUpWeb.SessionController do
  @moduledoc """
  Browser sign-in and sign-up.

  Plain controller rather than LiveView on purpose: these are the two pages a
  logged-out stranger hits first, and they should work before any websocket is
  established. Everything behind them is LiveView.

  The web app exists to remove the install barrier — someone follows a link to
  a duel, and the only thing between them and drafting is this form. So sign-up
  asks for the three fields the account genuinely needs and nothing else, and
  drops you straight back where you were headed.
  """
  use HeadsUpWeb, :controller

  alias HeadsUp.Accounts
  alias HeadsUpWeb.UserAuth

  # Same armor the API twins wear (auth_controller) — the website was the
  # unlimited side door for credential stuffing and free-account farming.
  plug HeadsUpWeb.Plugs.RateLimit, [limit: 10, window_ms: 60_000, key: "login"] when action == :create
  plug HeadsUpWeb.Plugs.RateLimit, [limit: 5, window_ms: 3_600_000, key: "register"] when action == :signup
  plug HeadsUpWeb.Plugs.RateLimit,
       [limit: 5, window_ms: 900_000, key: "password_forgot"] when action == :send_reset

  plug HeadsUpWeb.Plugs.RateLimit,
       [limit: 10, window_ms: 900_000, key: "password_reset"] when action == :do_reset

  def new(conn, _params), do: render(conn, :new, error: nil, email: nil)

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.get_user_by_email_and_password(email, password) do
      %Accounts.User{} = user ->
        return_to = UserAuth.return_path(conn)

        conn
        |> UserAuth.log_in_web_user(user)
        |> put_flash(:info, "Welcome back.")
        |> redirect(to: return_to)

      _ ->
        conn
        |> put_status(:unauthorized)
        |> render(:new, error: "That email and password don't match.", email: email)
    end
  end

  def new_signup(conn, _params), do: render(conn, :signup, changeset_errors: [], values: %{})

  def signup(conn, %{"user" => params}) do
    case Accounts.register_user(params) do
      {:ok, user} ->
        _ = HeadsUp.Coins.grant_signup(user.id)
        return_to = UserAuth.return_path(conn)

        conn
        |> UserAuth.log_in_web_user(user)
        |> put_flash(:info, "You're in. Go call someone out.")
        |> redirect(to: return_to)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:signup, changeset_errors: readable_errors(changeset), values: params)
    end
  end

  # Malformed POSTs (stripped forms, curl) get a 400 page, not a 500.
  def create(conn, _params) do
    conn |> put_status(:bad_request) |> render(:new, error: "That didn't come through right — try again.", email: nil)
  end

  def signup(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> render(:signup, changeset_errors: ["form: incomplete submission"], values: %{})
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_web_user()
  end

  # --- forgot / reset password (same engine as the phone: emailed code) -------

  def forgot(conn, params), do: render(conn, :forgot, email: params["email"])

  def send_reset(conn, %{"user" => %{"email" => email}}) do
    # Fire-and-forget on purpose — the answer never reveals whether the
    # account exists (the API twin behaves identically).
    _ = Accounts.deliver_password_reset(String.trim(to_string(email)))

    conn
    |> put_flash(:info, "If that email has an account, a 6-digit code is on the way.")
    |> redirect(to: ~p"/reset-password?email=#{String.trim(to_string(email))}")
  end

  def send_reset(conn, _params) do
    conn |> put_status(:bad_request) |> render(:forgot, email: nil)
  end

  def reset(conn, params), do: render(conn, :reset, email: params["email"], error: nil)

  def do_reset(conn, %{"user" => %{"email" => email, "code" => code, "password" => password}}) do
    case Accounts.reset_password(String.trim(to_string(email)), String.trim(to_string(code)), password) do
      {:ok, user} ->
        # Every old session just died (by design); start a fresh one here.
        conn
        |> UserAuth.log_in_web_user(user)
        |> put_flash(:info, "Password changed — you're signed in.")
        |> redirect(to: "/app")

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:reset, email: email, error: readable_errors(changeset) |> Enum.join(" · "))

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:reset, email: email, error: "That code isn't right, or it expired. Codes last 15 minutes.")
    end
  end

  def do_reset(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> render(:reset, email: nil, error: "That didn't come through right — try again.")
  end

  # Ecto errors as plain "field: message" strings — the form is hand-written
  # rather than generated, so it wants sentences, not a changeset.
  defp readable_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), "") |> to_string()
      end)
    end)
    |> Enum.map(fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
  end
end
