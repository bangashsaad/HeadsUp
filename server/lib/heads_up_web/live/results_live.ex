defmodule HeadsUpWeb.ResultsLive do
  @moduledoc """
  A settled duel's final scoreboard — who won, both lineups with every
  player's points, the coin outcome, and the same trash-talk thread the live
  screen carries (receipts stay open after the whistle).

  Renders from the SAME frozen breakdown the phone's Results screen reads
  (`ResultJSON.data/3`), so history can never disagree between platforms.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.{Contests, Settlement}
  alias HeadsUpWeb.ResultJSON

  @impl true
  def mount(%{"id" => id_str}, _session, socket) do
    user = socket.assigns.current_user

    with {duel_id, ""} <- Integer.parse(id_str),
         %{} = duel <- Contests.get_duel(user, duel_id),
         %{} = result <- Settlement.get_result(duel_id) do
      if connected?(socket), do: Phoenix.PubSub.subscribe(HeadsUp.PubSub, "duel_chat:#{duel_id}")

      chat =
        case Contests.list_messages(user, duel_id) do
          {:ok, messages} -> messages
          _ -> []
        end

      {:ok,
       socket
       |> assign(page_title: "Result", duel_id: duel_id, chat: chat, draft: "")
       |> assign(r: ResultJSON.data(result, duel, user.id), sport: duel.sport)}
    else
      _ ->
        {:ok, socket |> put_flash(:error, "No result there yet.") |> redirect(to: "/app/duels")}
    end
  end

  @impl true
  def handle_info({:duel_message, message}, socket),
    do: {:noreply, update(socket, :chat, &(&1 ++ [message]))}

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("draft", %{"body" => body}, socket), do: {:noreply, assign(socket, draft: body)}

  def handle_event("send", %{"body" => body}, socket) do
    case Contests.post_message(socket.assigns.current_user, socket.assigns.duel_id, body) do
      {:ok, _} -> {:noreply, assign(socket, draft: "")}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("rematch", _params, socket) do
    case Contests.rematch(socket.assigns.current_user, socket.assigns.duel_id) do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Rematch sent — same terms.") |> push_navigate(to: "/app/duels")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't rematch (#{inspect(reason)}).")}
    end
  end

  # --- render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash}>
      <div class="mx-auto max-w-2xl">
        <div class={[
          "rounded-2xl border p-6 text-center",
          @r.my_outcome == "win" && "border-[#C8FF2E]/50 bg-[#C8FF2E]/10",
          @r.my_outcome == "loss" && "border-[#FF4557]/40 bg-[#FF4557]/5",
          @r.my_outcome == "tie" && "border-[#252A3A] bg-[#12141D]"
        ]}>
          <p class="hu-cond text-4xl uppercase tracking-wide">
            {case @r.my_outcome do
              "win" -> "You took it 🏆"
              "loss" -> "They got you"
              _ -> "Dead even"
            end}
          </p>
          <p :if={@r.pot_coins > 0} class="mt-1.5 text-sm font-bold text-[#8B91A7]">
            {cond do
              @r.my_outcome == "win" -> "◎ #{@r.pot_coins} pot — yours"
              @r.my_outcome == "tie" -> "Stakes returned"
              true -> "◎ #{@r.stake_coins} to the winner"
            end}
          </p>
        </div>

        <div class="mt-4 space-y-3">
          <.lineup :for={side <- @r.standings} side={side} sport={@sport} />
        </div>

        <button
          :if={length(@r.standings) == 2}
          phx-click="rematch"
          class="mt-5 w-full rounded-xl bg-[#C8FF2E] px-4 py-3.5 text-sm font-black uppercase tracking-wide text-[#0A0B10] hover:brightness-110"
        >
          Run it back — same terms
        </button>

        <.thread chat={@chat} draft={@draft} me={@current_user.id} />
      </div>
    </Layouts.shell>
    """
  end

  attr :side, :map, required: true
  attr :sport, :string, required: true

  defp lineup(assigns) do
    ~H"""
    <div class="rounded-xl border border-[#1A1E2B] bg-[#12141D] p-4">
      <div class="mb-2.5 flex items-baseline justify-between">
        <p class={[
          "text-[12px] font-black uppercase tracking-wider",
          if(@side.is_me, do: "text-[#C8FF2E]", else: "text-[#9F8BFF]")
        ]}>
          {ordinal(@side.rank)} · {if @side.is_me, do: "You", else: @side.username || "them"}
        </p>
        <p class="text-xl font-black tabular-nums">{@side.total}</p>
      </div>
      <ul class="space-y-1.5">
        <li :for={p <- @side.players} class="flex items-center gap-2 text-sm">
          <span class="w-10 flex-none text-[10px] font-black uppercase text-[#565D73]">{p.slot}</span>
          <span class="min-w-0 flex-1 truncate">{p.name}</span>
          <span class="flex-none truncate text-[11px] text-[#8B91A7]">
            {HeadsUp.Sports.StatLine.format(@sport, p.stat_line)}
          </span>
          <span class="w-12 flex-none text-right font-black tabular-nums">{p.points}</span>
        </li>
      </ul>
    </div>
    """
  end

  attr :chat, :list, required: true
  attr :draft, :string, required: true
  attr :me, :integer, required: true

  defp thread(assigns) do
    ~H"""
    <div class="mt-6 rounded-2xl border border-[#252A3A] bg-[#0D0F16]">
      <p class="border-b border-[#1A1E2B] px-4 py-3 text-sm font-black uppercase tracking-wide">
        Trash talk <span class="ml-1 text-[10px] font-bold text-[#565D73]">receipts stay open</span>
      </p>
      <div class="max-h-72 space-y-2.5 overflow-y-auto p-3.5" id="result-thread" phx-hook="ScrollToEnd">
        <p :if={@chat == []} class="py-4 text-center text-xs text-[#565D73]">Nothing said. Yet.</p>
        <div :for={m <- @chat} class={["flex flex-col gap-0.5", m.user_id == @me && "items-end"]}>
          <span class={[
            "text-[9.5px] font-black uppercase tracking-wider",
            if(m.user_id == @me, do: "text-[#C8FF2E]", else: "text-[#9F8BFF]")
          ]}>
            {if m.user_id == @me, do: "You", else: m.username}
          </span>
          <span class={[
            "max-w-[260px] rounded-xl border px-3 py-2 text-[13px] text-[#E6E8F0]",
            if(m.user_id == @me, do: "border-[#C8FF2E]/35 bg-[#C8FF2E]/10", else: "border-[#7C5CFF]/40 bg-[#7C5CFF]/10")
          ]}>
            {m.body}
          </span>
        </div>
      </div>
      <form phx-submit="send" phx-change="draft" id="result-chat-form" class="flex gap-2 border-t border-[#1A1E2B] p-3">
        <input
          type="text"
          name="body"
          value={@draft}
          maxlength="280"
          autocomplete="off"
          placeholder="Post the receipt…"
          class="min-w-0 flex-1 rounded-full border border-[#252A3A] bg-[#0D0F16] px-4 py-2.5 text-[13px] outline-none focus:border-[#C8FF2E]/60"
        />
        <button type="submit" class="h-10 w-10 flex-none rounded-full bg-[#C8FF2E] text-sm font-black text-[#0A0B10]">➤</button>
      </form>
    </div>
    """
  end

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(n), do: "#{n}th"
end
