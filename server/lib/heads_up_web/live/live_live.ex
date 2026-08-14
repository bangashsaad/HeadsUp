defmodule HeadsUpWeb.LiveLive do
  @moduledoc """
  The live matchup in a browser: both rosters scoring off real box scores,
  with the trash-talk rail beside them — the design's centerpiece screen.

  Scores refresh on a 15-second timer, the same cadence the phone polls at
  (the underlying provider data only moves that fast). Chat is faster than
  that: messages arrive over the `"duel_chat:<id>"` PubSub topic the moment
  anyone posts, phone or web.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.{Contests, Settlement}

  @tick_ms 15_000

  @impl true
  def mount(%{"id" => id_str}, _session, socket) do
    user = socket.assigns.current_user

    with {duel_id, ""} <- Integer.parse(id_str),
         %{} = duel <- Contests.get_duel(user, duel_id) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(HeadsUp.PubSub, "duel_chat:#{duel_id}")
        :timer.send_interval(@tick_ms, self(), :tick)
      end

      chat =
        case Contests.list_messages(user, duel_id) do
          {:ok, messages} -> messages
          _ -> []
        end

      {:ok,
       socket
       |> assign(page_title: "Live", duel_id: duel_id, duel: duel, chat: chat, draft: "")
       |> load_live()}
    else
      _ ->
        {:ok, socket |> put_flash(:error, "That duel isn't yours.") |> redirect(to: "/app")}
    end
  end

  defp load_live(socket) do
    case Settlement.live_result(socket.assigns.duel_id) do
      {:ok, live} ->
        assign(socket, live: render_live(live, socket.assigns.current_user.id), settled: false)

      # Settled while watching (or not started): the page degrades to the
      # thread alone, with a pointer to the result.
      {:error, _} ->
        assign(socket, live: nil, settled: true)
    end
  end

  # Reuse the exact JSON the phone renders, so the two screens can never
  # disagree about a score.
  defp render_live(live, uid) do
    HeadsUpWeb.LiveJSON.show(%{live: live, current_user_id: uid})
  end

  @impl true
  def handle_info(:tick, socket), do: {:noreply, load_live(socket)}

  def handle_info({:duel_message, message}, socket) do
    {:noreply, update(socket, :chat, &(&1 ++ [message]))}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("draft", %{"body" => body}, socket), do: {:noreply, assign(socket, draft: body)}

  def handle_event("send", %{"body" => body}, socket) do
    case Contests.post_message(socket.assigns.current_user, socket.assigns.duel_id, body) do
      # Our own message comes back via PubSub like everyone else's — one path.
      {:ok, _} -> {:noreply, assign(socket, draft: "")}
      {:error, %Ecto.Changeset{}} -> {:noreply, put_flash(socket, :error, "Keep it under 280.")}
      {:error, _} -> {:noreply, socket}
    end
  end

  # --- render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash}>
      <div class="grid gap-4 lg:grid-cols-[1fr_320px]">
        <div>
          <%= if @live do %>
            <.scoreboard live={@live} />
            <div class="mt-4 grid gap-3 sm:grid-cols-2">
              <.roster side={@live.challenger || Enum.at(@live.sides, 0)} mine_first={true} />
              <.roster side={@live.opponent || Enum.at(@live.sides, 1)} mine_first={false} />
            </div>
          <% else %>
            <div class="rounded-2xl border border-[#1A1E2B] bg-[#12141D] px-4 py-10 text-center">
              <p class="font-black">This one's decided.</p>
              <.link navigate={~p"/app/results/#{@duel_id}"} class="mt-2 inline-block text-sm font-bold text-[#C8FF2E] hover:underline">
                See the final result →
              </.link>
            </div>
          <% end %>
        </div>

        <.chat_rail chat={@chat} draft={@draft} me={@current_user.id} />
      </div>
    </Layouts.shell>
    """
  end

  attr :live, :map, required: true

  defp scoreboard(assigns) do
    [a, b | _] = assigns.live.sides ++ [nil, nil]
    assigns = assign(assigns, a: a, b: b)

    ~H"""
    <div class="rounded-2xl border border-[#252A3A] bg-[#12141D] p-5">
      <div class="mb-3 flex items-center justify-between">
        <span class="hu-cond text-[15px] tracking-[1px] text-[#8B91A7]">HEAD-TO-HEAD</span>
        <span class="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-wide text-[#FF4557]">
          <span class="inline-block h-1.5 w-1.5 animate-pulse rounded-full bg-[#FF4557]"></span> Live
        </span>
      </div>
      <div class="flex items-end justify-between">
        <div>
          <p class="text-[11px] font-black uppercase tracking-wide text-[#C8FF2E]">
            {if @a.is_me, do: "You", else: @a.user.username}
          </p>
          <p class="text-4xl font-black tabular-nums">{fmt(@a.total)}</p>
        </div>
        <span class="pb-1 text-sm font-black text-[#3A4157]">VS</span>
        <div class="text-right">
          <p class="text-[11px] font-black uppercase tracking-wide text-[#9F8BFF]">
            {if @b.is_me, do: "You", else: @b.user.username}
          </p>
          <p class="text-4xl font-black tabular-nums">{fmt(@b.total)}</p>
        </div>
      </div>
      <div :if={length(@live.sides) > 2} class="mt-3 border-t border-[#1A1E2B] pt-2 text-xs text-[#8B91A7]">
        <span :for={s <- Enum.drop(@live.sides, 2)} class="mr-4">
          {s.user.username} · <span class="font-bold text-[#F4F5F7]">{fmt(s.total)}</span>
        </span>
      </div>
    </div>
    """
  end

  attr :side, :map, required: true
  attr :mine_first, :boolean, default: false

  defp roster(assigns) do
    ~H"""
    <div :if={@side} class="rounded-xl border border-[#1A1E2B] bg-[#12141D] p-3">
      <p class={[
        "mb-2 text-[11px] font-black uppercase tracking-wider",
        if(@side.is_me, do: "text-[#C8FF2E]", else: "text-[#9F8BFF]")
      ]}>
        {if @side.is_me, do: "Your five", else: "#{@side.user.username}'s five"}
      </p>
      <ul class="space-y-2">
        <li :for={p <- @side.players} class="flex items-center gap-2.5">
          <img
            :if={p.headshot_url}
            src={p.headshot_url}
            class="h-8 w-8 flex-none rounded-full bg-[#191C28] object-cover"
            loading="lazy"
          />
          <div
            :if={!p.headshot_url}
            class="flex h-8 w-8 flex-none items-center justify-center rounded-full bg-[#191C28] text-[10px] font-black text-[#8B91A7]"
          >
            {initials(p.name)}
          </div>
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-bold">{p.name || "—"}</p>
            <p class="truncate text-[11px] text-[#8B91A7]">
              {p.line || "No line yet"}
              <span :if={p.game && p.game.state == "in"} class="text-[#FF4557]">· {p.game.detail}</span>
            </p>
          </div>
          <span class="flex-none text-sm font-black tabular-nums text-[#F4F5F7]">{fmt(p.points)}</span>
        </li>
      </ul>
    </div>
    """
  end

  attr :chat, :list, required: true
  attr :draft, :string, required: true
  attr :me, :integer, required: true

  defp chat_rail(assigns) do
    ~H"""
    <div class="flex max-h-[70vh] flex-col rounded-2xl border border-[#252A3A] bg-[#0D0F16]">
      <div class="flex flex-none items-center justify-between border-b border-[#1A1E2B] px-4 py-3">
        <span class="hu-cond text-[15px] tracking-[1px]">TRASH TALK</span>
        <span class="text-[10px] font-bold uppercase tracking-wide text-[#565D73]">Duel only</span>
      </div>

      <div class="flex-1 space-y-2.5 overflow-y-auto p-3.5" id="chat-thread" phx-hook="ScrollToEnd">
        <p :if={@chat == []} class="py-6 text-center text-xs text-[#565D73]">
          Say something. Scoreboard talk is free.
        </p>
        <div :for={m <- @chat} class={["flex flex-col gap-0.5", m.user_id == @me && "items-end"]}>
          <span class={[
            "text-[9.5px] font-black uppercase tracking-wider",
            if(m.user_id == @me, do: "text-[#C8FF2E]", else: "text-[#9F8BFF]")
          ]}>
            {if m.user_id == @me, do: "You", else: m.username}
          </span>
          <span class={[
            "max-w-[230px] rounded-xl border px-3 py-2 text-[13px] leading-snug text-[#E6E8F0]",
            if(m.user_id == @me,
              do: "border-[#C8FF2E]/35 bg-[#C8FF2E]/10",
              else: "border-[#7C5CFF]/40 bg-[#7C5CFF]/10"
            )
          ]}>
            {m.body}
          </span>
        </div>
      </div>

      <form phx-submit="send" phx-change="draft" id="chat-form" class="flex flex-none gap-2 border-t border-[#1A1E2B] p-3">
        <input
          type="text"
          name="body"
          value={@draft}
          maxlength="280"
          autocomplete="off"
          placeholder="Talk your talk…"
          class="min-w-0 flex-1 rounded-full border border-[#252A3A] bg-[#0D0F16] px-4 py-2.5 text-[13px] outline-none focus:border-[#C8FF2E]/60"
        />
        <button
          type="submit"
          class="h-10 w-10 flex-none rounded-full bg-[#C8FF2E] text-sm font-black text-[#0A0B10] hover:brightness-110"
        >
          ➤
        </button>
      </form>
    </div>
    """
  end

  defp fmt(nil), do: "0.0"
  defp fmt(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp fmt(n), do: to_string(n)

  defp initials(nil), do: "?"

  defp initials(name) do
    name |> String.split() |> Enum.map(&String.first/1) |> Enum.take(2) |> Enum.join()
  end
end
