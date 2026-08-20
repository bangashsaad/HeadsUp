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
    cond do
      HeadsUpWeb.Plugs.RateLimit.over_limit?(socket.assigns.current_user.id, "chat", 20, 60_000) ->
        {:noreply, put_flash(socket, :error, "Easy — a few messages a minute.")}

      true ->
        case Contests.post_message(socket.assigns.current_user, socket.assigns.duel_id, body) do
          {:ok, _} -> {:noreply, assign(socket, draft: "")}
          {:error, %Ecto.Changeset{}} -> {:noreply, put_flash(socket, :error, "Keep it under 280.")}
          {:error, _} -> {:noreply, put_flash(socket, :error, "That didn't send — try again.")}
        end
    end
  end

  def handle_event("rematch", _params, socket) do
    # Same verified-email gate the duels screen applies — this was the one
    # duel-creating action that skipped it.
    if HeadsUpWeb.UserAuth.verified_for_duels?(socket.assigns.current_user) do
      case Contests.rematch(socket.assigns.current_user, socket.assigns.duel_id) do
        {:ok, _} ->
          {:noreply,
           socket |> put_flash(:info, "Rematch sent — same terms.") |> push_navigate(to: "/app/duels")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Couldn't rematch (#{inspect(reason)}).")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Verify your email to duel — takes a few seconds.")
       |> push_navigate(to: "/app/verify")}
    end
  end

  # Tampered or unknown events must not crash the socket.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # --- render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash} shell={assigns[:shell] || %{}}>
      <div class="mx-auto max-w-2xl" style="animation:huw-rise .3s ease">
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:14px">
          <.link navigate={~p"/app/duels"} style="font-size:11px;font-weight:800;letter-spacing:1px;color:#8B91A7">← BACK TO DUELS</.link>
          <span style="font-size:11px;font-weight:800;letter-spacing:1px;color:#565D73">{String.upcase(@sport)} · SETTLED</span>
        </div>

        <%!-- his hero: the big letter, the badges, the score row, the actions --%>
        <div style={"position:relative;overflow:hidden;border-radius:18px;border:1px solid #{hero_border(@r.my_outcome)};background:#{hero_bg(@r.my_outcome)};padding:22px 24px;display:flex;gap:20px;align-items:center;flex-wrap:wrap"}>
          <div style={"width:84px;height:84px;flex:none;border-radius:22px;display:flex;align-items:center;justify-content:center;background:#{letter_bg(@r.my_outcome)};border:1px solid #{hero_border(@r.my_outcome)}"}>
            <span class="hu-cond" style={"font-size:52px;color:#{letter_ink(@r.my_outcome)}"}>{letter(@r.my_outcome)}</span>
          </div>
          <div style="flex:1;min-width:240px;display:flex;flex-direction:column;gap:8px">
            <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
              <span style={"font-size:10px;font-weight:900;letter-spacing:1.5px;color:#{letter_ink(@r.my_outcome)}"}>{badge_text(@r.my_outcome)}</span>
              <span :if={@r.pot_coins > 0 and @r.my_outcome == "win"} style="font-size:12px;font-weight:800;color:#FFB021">◎ +{@r.pot_coins - @r.stake_coins}</span>
              <span :if={@r.stake_coins > 0 and @r.my_outcome == "loss"} style="font-size:12px;font-weight:800;color:#565D73">◎ −{@r.stake_coins}</span>
            </div>
            <div class="hu-cond" style="font-size:34px;line-height:1">{title(@r.my_outcome)}<span style="color:var(--acc,#C8FF2E)">.</span></div>
            <div :if={length(@r.standings) == 2} style="display:flex;align-items:center;gap:18px">
              <div :for={side <- @r.standings} style="display:flex;align-items:baseline;gap:8px">
                <span style={"font-size:11px;font-weight:900;letter-spacing:1px;color:#{if side.is_me, do: "var(--acc,#C8FF2E)", else: "#8B91A7"}"}>
                  {if side.is_me, do: "YOU", else: String.upcase(side.username || "THEM")}
                </span>
                <span class="hu-cond" style="font-size:28px">{side.total}</span>
              </div>
            </div>
            <div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:4px">
              <button
                :if={length(@r.standings) == 2}
                phx-click="rematch"
                class="hu-cond"
                style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:16px;letter-spacing:.5px;border-radius:999px;padding:11px 24px;border:none"
              >
                REMATCH · SAME TERMS →
              </button>
              <button
                id="share-receipt"
                phx-hook="CopyLink"
                class="hu-cond"
                style="cursor:pointer;border:1px solid #252A3A;color:#8B91A7;font-size:16px;letter-spacing:.5px;border-radius:999px;padding:11px 24px;background:transparent"
              >
                SHARE THE RECEIPT
              </button>
            </div>
          </div>
        </div>

        <div class="mt-4 space-y-3">
          <.lineup :for={side <- @r.standings} side={side} sport={@sport} />
        </div>

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

  defp letter("win"), do: "W"
  defp letter("loss"), do: "L"
  defp letter(_), do: "T"

  defp letter_ink("win"), do: "var(--acc,#C8FF2E)"
  defp letter_ink("loss"), do: "#FF4557"
  defp letter_ink(_), do: "#8B91A7"

  defp letter_bg("win"), do: "rgba(200,255,46,.1)"
  defp letter_bg("loss"), do: "rgba(255,69,87,.08)"
  defp letter_bg(_), do: "rgba(139,145,167,.08)"

  defp hero_border("win"), do: "rgba(200,255,46,.45)"
  defp hero_border("loss"), do: "rgba(255,69,87,.4)"
  defp hero_border(_), do: "#252A3A"

  defp hero_bg("win"),
    do: "radial-gradient(500px 240px at 10% 0%,rgba(200,255,46,.12),transparent 65%),#12141D"

  defp hero_bg("loss"),
    do: "radial-gradient(500px 240px at 10% 0%,rgba(255,69,87,.1),transparent 65%),#12141D"

  defp hero_bg(_), do: "#12141D"

  defp badge_text("win"), do: "VICTORY"
  defp badge_text("loss"), do: "SETTLED"
  defp badge_text(_), do: "DEAD EVEN"

  defp title("win"), do: "YOU TOOK IT"
  defp title("loss"), do: "THEY GOT YOU"
  defp title(_), do: "SPLIT THE NIGHT"
end
