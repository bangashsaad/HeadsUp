defmodule HeadsUpWeb.DuelsLive do
  @moduledoc """
  Every duel you're part of — the web counterpart of the app's Duels tab.

  Same split the app uses: ACTIVE is anything that still wants something from
  someone (pending/accepted/drafting/drafted), PAST is settled plus the
  declined and cancelled. Actions mirror the app exactly: accept, decline,
  cancel, rematch. Countering opens the challenge form seeded with the duel's
  terms, same as the phone.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.Contests

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Duels", tab: "active") |> load()}
  end

  defp load(socket) do
    user = socket.assigns.current_user
    duels = Contests.list_duels(user)

    active = Enum.filter(duels, &(&1.status in ~w(pending accepted drafting drafted)))
    past = Enum.filter(duels, &(&1.status in ~w(settled declined cancelled expired)))

    assign(socket, active: active, past: past)
  end

  @impl true
  def handle_event("tab", %{"tab" => tab}, socket) when tab in ~w(active past) do
    {:noreply, assign(socket, tab: tab)}
  end

  def handle_event("accept", %{"id" => id}, socket) do
    case Contests.accept_challenge(socket.assigns.current_user, String.to_integer(id)) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Locked in. Draft time.") |> load()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, humanize(reason))}
    end
  end

  def handle_event("decline", %{"id" => id}, socket) do
    case Contests.decline_challenge(socket.assigns.current_user, String.to_integer(id)) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Declined.") |> load()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, humanize(reason))}
    end
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    case Contests.cancel_challenge(socket.assigns.current_user, String.to_integer(id)) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Called off.") |> load()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, humanize(reason))}
    end
  end

  def handle_event("rematch", %{"id" => id}, socket) do
    case Contests.rematch(socket.assigns.current_user, String.to_integer(id)) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Rematch sent — same terms.") |> load()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, humanize(reason))}
    end
  end

  defp humanize(reason) when is_binary(reason), do: reason
  defp humanize(reason), do: "Couldn't do that (#{inspect(reason)})."

  # --- render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash}>
      <div class="mb-5 flex items-center justify-between">
        <h1 class="hu-cond text-3xl tracking-wide">DUELS</h1>
        <.link
          navigate={~p"/app/new"}
          class="rounded-lg bg-[#C8FF2E] px-3.5 py-2 text-xs font-black uppercase tracking-wide text-[#0A0B10] hover:brightness-110"
        >
          + New challenge
        </.link>
      </div>

      <div class="mb-5 flex gap-1 rounded-xl border border-[#1A1E2B] bg-[#0D0F16] p-1">
        <button
          :for={{key, label} <- [{"active", "Active"}, {"past", "Past"}]}
          phx-click="tab"
          phx-value-tab={key}
          class={[
            "flex-1 rounded-lg px-3 py-2 text-xs font-black uppercase tracking-wide",
            if(@tab == key, do: "bg-[#C8FF2E] text-[#0A0B10]", else: "text-[#8B91A7] hover:text-[#F4F5F7]")
          ]}
        >
          {label}
        </button>
      </div>

      <div :if={@tab == "active"}>
        <p :if={@active == []} class="rounded-xl border border-[#1A1E2B] bg-[#12141D] px-4 py-8 text-center text-sm text-[#565D73]">
          Nothing going. Call somebody out.
        </p>
        <ul class="space-y-2.5">
          <li :for={duel <- @active}><.duel_card duel={duel} me={@current_user.id} /></li>
        </ul>
      </div>

      <div :if={@tab == "past"}>
        <p :if={@past == []} class="rounded-xl border border-[#1A1E2B] bg-[#12141D] px-4 py-8 text-center text-sm text-[#565D73]">
          No history yet.
        </p>
        <ul class="space-y-2.5">
          <li :for={duel <- @past}><.past_card duel={duel} me={@current_user.id} /></li>
        </ul>
      </div>
    </Layouts.shell>
    """
  end

  attr :duel, :map, required: true
  attr :me, :integer, required: true

  defp duel_card(assigns) do
    d = assigns.duel
    me = assigns.me

    assigns =
      assign(assigns,
        vs: vs_name(d, me),
        meta: meta_line(d),
        i_was_challenged: d.status == "pending" and challenged?(d, me),
        i_sent_it: d.status == "pending" and not challenged?(d, me)
      )

    ~H"""
    <div class="rounded-xl border border-[#252A3A] bg-[#12141D] p-4">
      <div class="flex items-start justify-between gap-3">
        <div class="min-w-0">
          <p class="truncate font-black">{@vs}</p>
          <p class="mt-0.5 text-xs text-[#8B91A7]">{@meta}</p>
        </div>
        <span class={[
          "flex-none rounded-md px-2 py-1 text-[10px] font-black uppercase tracking-wide",
          status_tone(@duel.status)
        ]}>
          {status_label(@duel.status, @i_was_challenged)}
        </span>
      </div>

      <div class="mt-3 flex flex-wrap gap-2">
        <%= cond do %>
          <% @i_was_challenged -> %>
            <.act click="accept" id={@duel.id} primary>Accept</.act>
            <.act click="decline" id={@duel.id}>Decline</.act>
            <.link navigate={~p"/app/new?counter=#{@duel.id}"} class={btn(false)}>Counter</.link>
          <% @i_sent_it -> %>
            <.act click="cancel" id={@duel.id}>Cancel</.act>
          <% @duel.status in ["accepted", "drafting"] -> %>
            <.link navigate={~p"/app/draft/#{@duel.id}"} class={btn(true)}>Enter draft room →</.link>
          <% @duel.status == "drafted" -> %>
            <.link navigate={~p"/app/live/#{@duel.id}"} class={btn(true)}>Watch live →</.link>
          <% true -> %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :duel, :map, required: true
  attr :me, :integer, required: true

  defp past_card(assigns) do
    d = assigns.duel
    me = assigns.me

    outcome =
      cond do
        d.status != "settled" -> nil
        d.winner_id == nil -> "T"
        d.winner_id == me -> "W"
        true -> "L"
      end

    assigns = assign(assigns, vs: vs_name(d, me), meta: meta_line(d), outcome: outcome)

    ~H"""
    <div class="flex items-center gap-3 rounded-xl border border-[#1A1E2B] bg-[#12141D] p-4">
      <span
        :if={@outcome}
        class={[
          "flex h-9 w-9 flex-none items-center justify-center rounded-full text-sm font-black",
          @outcome == "W" && "bg-[#C8FF2E]/15 text-[#C8FF2E]",
          @outcome == "L" && "bg-[#FF4557]/15 text-[#FF4557]",
          @outcome == "T" && "bg-[#8B91A7]/15 text-[#8B91A7]"
        ]}
      >
        {@outcome}
      </span>
      <div class="min-w-0 flex-1">
        <p class="truncate font-bold">{@vs}</p>
        <p class="text-xs text-[#8B91A7]">{@meta}</p>
      </div>
      <.link
        :if={@outcome}
        navigate={~p"/app/results/#{@duel.id}"}
        class="flex-none text-xs font-black uppercase tracking-wide text-[#C8FF2E] hover:underline"
      >
        Result
      </.link>
      <button
        :if={@outcome && !group?(@duel)}
        phx-click="rematch"
        phx-value-id={@duel.id}
        class="flex-none rounded-lg border border-[#252A3A] px-3 py-1.5 text-xs font-bold uppercase tracking-wide text-[#F4F5F7] hover:border-[#C8FF2E]/50"
      >
        Rematch
      </button>
    </div>
    """
  end

  attr :click, :string, required: true
  attr :id, :integer, required: true
  attr :primary, :boolean, default: false
  slot :inner_block, required: true

  defp act(assigns) do
    ~H"""
    <button phx-click={@click} phx-value-id={@id} class={btn(@primary)}>{render_slot(@inner_block)}</button>
    """
  end

  defp btn(true),
    do: "rounded-lg bg-[#C8FF2E] px-3.5 py-2 text-xs font-black uppercase tracking-wide text-[#0A0B10] hover:brightness-110"

  defp btn(false),
    do: "rounded-lg border border-[#252A3A] px-3.5 py-2 text-xs font-bold uppercase tracking-wide text-[#F4F5F7] hover:border-[#C8FF2E]/50"

  # --- labels ---------------------------------------------------------------

  defp group?(d), do: d.opponent_id == nil

  defp challenged?(d, me) do
    if group?(d) do
      Enum.any?(d.participants, &(&1.user_id == me and &1.status == "invited"))
    else
      d.opponent_id == me
    end
  end

  defp vs_name(d, me) do
    cond do
      group?(d) ->
        host = Enum.find(d.participants, &(&1.seat == 0))
        n = length(d.participants)
        "#{(host && host.user.username) || "group"}'s #{n}-player match"

      d.challenger_id == me ->
        "vs #{d.opponent && d.opponent.username}"

      true ->
        "vs #{d.challenger && d.challenger.username}"
    end
  end

  defp meta_line(d) do
    sport = String.upcase(d.sport)
    stake = if d.stake_coins > 0, do: " · ◎ #{d.stake_coins} stake", else: " · friendly"
    "#{sport} · #{d.roster_size} slots#{stake}"
  end

  defp status_label("pending", true), do: "your call"
  defp status_label("pending", _), do: "waiting"
  defp status_label("accepted", _), do: "draft set"
  defp status_label("drafting", _), do: "drafting"
  defp status_label("drafted", _), do: "live"
  defp status_label(other, _), do: other

  defp status_tone("pending"), do: "bg-[#FFB021]/15 text-[#FFB021]"
  defp status_tone("accepted"), do: "bg-[#C8FF2E]/15 text-[#C8FF2E]"
  defp status_tone("drafting"), do: "bg-[#C8FF2E]/15 text-[#C8FF2E]"
  defp status_tone("drafted"), do: "bg-[#FF4557]/15 text-[#FF4557]"
  defp status_tone(_), do: "bg-[#8B91A7]/15 text-[#8B91A7]"
end
