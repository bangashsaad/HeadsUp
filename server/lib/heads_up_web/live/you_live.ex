defmodule HeadsUpWeb.YouLive do
  @moduledoc """
  Who you are here: season record, friend standings, your rivalries — and the
  account controls the design forgot but the product cannot ship without
  (App Store parity): change password, sign out everywhere, and delete the
  account. Blocking lives on the rival rows, same as the app's user profile.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.{Accounts, Coins, Social, Stats}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "You", danger: nil) |> load()}
  end

  defp load(socket) do
    user = socket.assigns.current_user

    assign(socket,
      record: Stats.record_for(user.id),
      h2h: Stats.head_to_head(user.id),
      leaderboard: Stats.leaderboard(user),
      coins: Coins.balance(user.id)
    )
  end

  @impl true
  def handle_event("danger", %{"which" => which}, socket) do
    {:noreply, assign(socket, danger: which)}
  end

  def handle_event("danger-close", _params, socket), do: {:noreply, assign(socket, danger: nil)}

  def handle_event("change-password", %{"current" => cur, "new" => new}, socket) do
    case Accounts.update_user_password(socket.assigns.current_user, cur, %{"password" => new}) do
      {:ok, _} ->
        {:noreply, socket |> assign(danger: nil) |> put_flash(:info, "Password changed.")}

      {:error, :invalid_current_password} ->
        {:noreply, put_flash(socket, :error, "That current password isn't right.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "New password needs at least 8 characters.")}
    end
  end

  def handle_event("block", %{"id" => id}, socket) do
    case Social.block_user(socket.assigns.current_user, String.to_integer(id)) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Blocked.") |> load()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't block them.")}
    end
  end

  def handle_event("delete-account", %{"password" => password}, socket) do
    case Accounts.delete_account(socket.assigns.current_user, password) do
      {:ok, _} ->
        # Every token died with the account, so the session cookie is inert —
        # the next request lands logged out.
        {:noreply, redirect(socket, to: "/")}

      {:error, :invalid_current_password} ->
        {:noreply, put_flash(socket, :error, "Password doesn't match — account untouched.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't delete the account.")}
    end
  end

  # --- render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash}>
      <div class="mx-auto max-w-2xl">
        <div class="flex items-baseline justify-between">
          <h1 class="text-2xl font-black">{@current_user.username}</h1>
          <span class="text-sm font-bold text-[#C8FF2E]">◎ {@coins}</span>
        </div>

        <div class="mt-4 grid grid-cols-3 gap-3">
          <.stat label="Record" value={"#{@record.wins}–#{@record.losses}"} />
          <.stat label="Win rate" value={pct(@record)} />
          <.stat
            label="Streak"
            value={if @record.streak && @record.streak.count > 0, do: "#{@record.streak.count}#{String.first(@record.streak.type)}", else: "—"}
          />
        </div>

        <h2 class="mb-2 mt-8 text-[11px] font-black uppercase tracking-[0.18em] text-[#8B91A7]">
          Friend standings
        </h2>
        <ol class="space-y-1.5">
          <li
            :for={{row, i} <- Enum.with_index(@leaderboard, 1)}
            class={[
              "flex items-center gap-3 rounded-xl border px-3.5 py-2.5",
              if(row.user.id == @current_user.id,
                do: "border-[#C8FF2E]/45 bg-[#C8FF2E]/5",
                else: "border-[#1A1E2B] bg-[#12141D]"
              )
            ]}
          >
            <span class="w-5 flex-none text-xs font-black text-[#565D73]">#{i}</span>
            <span class="min-w-0 flex-1 truncate text-sm font-bold">
              {if row.user.id == @current_user.id, do: "You", else: row.user.username}
            </span>
            <span class="flex-none text-sm font-black tabular-nums">{row.wins}–{row.losses}</span>
          </li>
        </ol>

        <h2 class="mb-2 mt-8 text-[11px] font-black uppercase tracking-[0.18em] text-[#8B91A7]">
          Your rivalries
        </h2>
        <p :if={@h2h == []} class="rounded-xl border border-[#1A1E2B] bg-[#12141D] px-4 py-6 text-center text-sm text-[#565D73]">
          Finish a duel and the rivalry ledger starts.
        </p>
        <ul class="space-y-1.5">
          <li :for={r <- @h2h} class="flex items-center gap-3 rounded-xl border border-[#1A1E2B] bg-[#12141D] px-3.5 py-2.5">
            <span class="min-w-0 flex-1 truncate text-sm font-bold">{r.opponent.username}</span>
            <span class={[
              "flex-none text-sm font-black tabular-nums",
              if(r.wins >= r.losses, do: "text-[#C8FF2E]", else: "text-[#FF4557]")
            ]}>
              {r.wins}–{r.losses}
            </span>
            <button
              phx-click="block"
              phx-value-id={r.opponent.id}
              data-confirm={"Block #{r.opponent.username}? Shared live duels get cancelled and you disappear from each other."}
              class="flex-none text-[10px] font-bold uppercase tracking-wide text-[#565D73] hover:text-[#FF4557]"
            >
              Block
            </button>
          </li>
        </ul>

        <h2 class="mb-2 mt-10 text-[11px] font-black uppercase tracking-[0.18em] text-[#8B91A7]">
          Account
        </h2>
        <div class="space-y-2">
          <button phx-click="danger" phx-value-which="password" class={row_btn()}>
            Change password
          </button>
          <.link href="/logout" method="delete" class={row_btn() <> " block text-left"}>
            Sign out
          </.link>
          <button phx-click="danger" phx-value-which="delete" class={row_btn() <> " !text-[#FF4557]"}>
            Delete account
          </button>
        </div>

        <div :if={@danger == "password"} class="mt-4 rounded-xl border border-[#252A3A] bg-[#12141D] p-4">
          <form phx-submit="change-password" class="space-y-3">
            <input type="password" name="current" required placeholder="Current password" class={input()} />
            <input type="password" name="new" required minlength="8" placeholder="New password (8+ characters)" class={input()} />
            <div class="flex gap-2">
              <button type="submit" class="rounded-lg bg-[#C8FF2E] px-4 py-2.5 text-xs font-black uppercase text-[#0A0B10]">
                Change it
              </button>
              <button type="button" phx-click="danger-close" class="rounded-lg border border-[#252A3A] px-4 py-2.5 text-xs font-bold uppercase text-[#8B91A7]">
                Never mind
              </button>
            </div>
          </form>
        </div>

        <div :if={@danger == "delete"} class="mt-4 rounded-xl border border-[#FF4557]/40 bg-[#FF4557]/5 p-4">
          <p class="text-sm font-bold text-[#FF4557]">This is permanent.</p>
          <p class="mt-1 text-xs text-[#8B91A7]">
            Your account is anonymized and unusable. Finished duels stay on your rivals' records —
            history doesn't unhappen — but your name comes off everything.
          </p>
          <form phx-submit="delete-account" class="mt-3 space-y-3">
            <input type="password" name="password" required placeholder="Your password, to confirm" class={input()} />
            <button
              type="submit"
              data-confirm="Absolutely sure? There is no undo."
              class="rounded-lg bg-[#FF4557] px-4 py-2.5 text-xs font-black uppercase text-white"
            >
              Delete my account
            </button>
          </form>
        </div>
      </div>
    </Layouts.shell>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp stat(assigns) do
    ~H"""
    <div class="rounded-xl border border-[#1A1E2B] bg-[#12141D] p-3 text-center">
      <p class="text-xl font-black tabular-nums">{@value}</p>
      <p class="mt-0.5 text-[10px] font-black uppercase tracking-wider text-[#8B91A7]">{@label}</p>
    </div>
    """
  end

  defp pct(%{wins: w, losses: l}) when w + l > 0, do: "#{round(w / (w + l) * 100)}%"
  defp pct(_), do: "—"

  defp row_btn,
    do:
      "w-full rounded-xl border border-[#252A3A] bg-[#12141D] px-4 py-3 text-left text-sm font-bold text-[#F4F5F7] hover:border-[#C8FF2E]/40"

  defp input,
    do:
      "w-full rounded-xl border border-[#252A3A] bg-[#0D0F16] px-4 py-2.5 text-sm outline-none focus:border-[#C8FF2E]/60"
end
