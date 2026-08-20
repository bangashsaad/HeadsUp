defmodule HeadsUpWeb.VerifyLive do
  @moduledoc """
  Email verification on the web — the phone has had this gate since publish;
  the web shipped without it, which meant a browser signup could duel with an
  unverified address while a phone couldn't. Same code flow as the app: we
  email a 6-digit code, you type it, challenges unlock.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.Accounts

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    if user.email_verified_at do
      {:ok, socket |> put_flash(:info, "You're already verified.") |> redirect(to: "/app")}
    else
      # First arrival sends the code without an extra tap — but reconnects and
      # refreshes must NOT re-issue (issuing replaces the code the user is
      # about to type from their inbox).
      if connected?(socket), do: Accounts.ensure_email_verification(user)

      {:ok, assign(socket, page_title: "Verify your email", sent: true, error: nil)}
    end
  end

  # LiveView events bypass plugs, so the API's rate limits don't cover this
  # surface — a 6-digit code needs its guessing window capped here too.
  @impl true
  def handle_event("resend", _params, socket) do
    user = socket.assigns.current_user

    if HeadsUpWeb.Plugs.RateLimit.over_limit?(user.id, "verify-resend", 3, 900_000) do
      {:noreply, put_flash(socket, :error, "Give the inbox a minute — the last code is on its way.")}
    else
      Accounts.deliver_email_verification(user)
      {:noreply, socket |> assign(sent: true) |> put_flash(:info, "New code sent.")}
    end
  end

  def handle_event("confirm", %{"code" => code}, socket) do
    user = socket.assigns.current_user

    cond do
      HeadsUpWeb.Plugs.RateLimit.over_limit?(user.id, "verify-confirm", 10, 900_000) ->
        {:noreply, assign(socket, error: "Too many tries — wait a few minutes and use the newest code.")}

      true ->
        case Accounts.verify_email(user, String.trim(code)) do
          {:ok, _user} ->
            {:noreply,
             socket
             |> put_flash(:info, "Verified. Challenges unlocked.")
             |> redirect(to: "/app")}

          {:error, _} ->
            {:noreply, assign(socket, error: "That code isn't right (or it expired). Try again or resend.")}
        end
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash} shell={assigns[:shell] || %{}}>
      <div style="max-width:420px;margin:40px auto;display:flex;flex-direction:column;gap:14px;animation:huw-rise .3s ease">
        <span class="hu-cond" style="font-size:24px;letter-spacing:.5px">VERIFY YOUR EMAIL</span>
        <p style="font-size:12.5px;color:#8B91A7;font-weight:600;line-height:1.5">
          We sent a 6-digit code to <span style="color:#F4F5F7;font-weight:800">{@current_user.email}</span>.
          Enter it below and challenges unlock. Codes last 15 minutes.
        </p>

        <p :if={@error} style="font-size:12px;font-weight:700;color:#FF4557">{@error}</p>

        <form phx-submit="confirm" style="display:flex;gap:8px">
          <input
            type="text"
            name="code"
            inputmode="numeric"
            pattern="[0-9]*"
            maxlength="6"
            required
            autocomplete="one-time-code"
            placeholder="123456"
            style="flex:1;min-width:0;background:#0D0F16;border:1px solid #252A3A;border-radius:12px;padding:12px 16px;color:#F4F5F7;font-family:'Barlow Condensed',sans-serif;font-size:22px;letter-spacing:6px;outline:none;text-align:center"
          />
          <button
            type="submit"
            class="hu-cond"
            style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:16px;border-radius:12px;padding:12px 22px;border:none"
          >
            UNLOCK →
          </button>
        </form>

        <button
          phx-click="resend"
          style="cursor:pointer;align-self:flex-start;font-size:11px;font-weight:800;letter-spacing:.5px;color:#8B91A7;background:transparent;border:none;text-decoration:underline"
        >
          Resend the code
        </button>
      </div>
    </Layouts.shell>
    """
  end
end
