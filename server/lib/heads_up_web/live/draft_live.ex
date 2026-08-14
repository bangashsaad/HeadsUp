defmodule HeadsUpWeb.DraftLive do
  @moduledoc """
  The live draft, in a browser.

  This is the screen the whole web plan hinged on, and it turned out to be the
  cheapest rather than the most expensive: the draft engine already lives
  server-side in a GenServer that broadcasts a full snapshot on every change.
  The phone's channel subscribes to `"draft:<duel_id>"` and pushes those
  snapshots down a websocket; this LiveView subscribes to the SAME topic and
  renders them. No second engine, no duplicated clock, no reimplemented snake
  order — a browser is simply another subscriber, and both can sit in the same
  draft at once.

  Intents go back through the same `Drafts.Server` calls the channel makes, so
  a pick from a laptop and a pick from a phone are indistinguishable to the
  engine.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.{Contests, Drafts}
  alias HeadsUp.Drafts.{Server, Supervisor}

  @impl true
  def mount(%{"id" => duel_id_str}, _session, socket) do
    user = socket.assigns.current_user

    with {duel_id, ""} <- Integer.parse(duel_id_str),
         %Contests.Duel{} = duel <- Contests.get_duel_for_draft(user.id, duel_id),
         {:ok, draft} <- Drafts.get_or_create_draft_for_duel(duel),
         {:ok, _pid} <- Supervisor.ensure_started(draft.id, duel) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(HeadsUp.PubSub, "draft:#{duel_id}")
        Server.reconnected(draft.id, user.id)
      end

      {:ok,
       socket
       |> assign(duel_id: duel_id, draft_id: draft.id, page_title: "Draft")
       |> assign(state: Server.get_state(draft.id))
       |> assign(search: "")}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "That draft isn't yours to join.")
         |> redirect(to: "/app")}
    end
  end

  # Every engine change arrives as a full snapshot, so rendering is a straight
  # replace rather than a patch — the same contract the phones get.
  @impl true
  def handle_info({:draft_update, %{state: state}}, socket) do
    {:noreply, assign(socket, state: state)}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  def handle_event("ready", _params, socket) do
    Server.ready(socket.assigns.draft_id, socket.assigns.current_user.id)
    {:noreply, socket}
  end

  def handle_event("pick", %{"player-id" => id}, socket) do
    case Server.make_pick(socket.assigns.draft_id, socket.assigns.current_user.id, String.to_integer(id)) do
      {:error, reason} -> {:noreply, put_flash(socket, :error, pick_error(reason))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("search", %{"q" => q}, socket), do: {:noreply, assign(socket, search: q)}

  defp pick_error(:not_your_turn), do: "It's not your pick."
  defp pick_error(:already_drafted), do: "Someone just took that player."
  defp pick_error(:no_slot), do: "No open roster slot for that position."
  defp pick_error(other), do: "Couldn't make that pick (#{inspect(other)})."

  # --- render ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash}>
      <%= if @state.phase == :lobby or @state.phase == "lobby" do %>
        <.lobby state={@state} me={@current_user.id} />
      <% else %>
        <.board state={@state} me={@current_user.id} search={@search} />
      <% end %>
    </Layouts.shell>
    """
  end

  attr :state, :map, required: true
  attr :me, :integer, required: true

  defp lobby(assigns) do
    ~H"""
    <div class="mx-auto max-w-md py-8 text-center">
      <p class="text-[11px] font-black uppercase tracking-[0.2em] text-[#8B91A7]">Draft lobby</p>
      <h1 class="mt-2 text-2xl font-black">Waiting on everyone</h1>

      <ul class="mt-7 space-y-2">
        <li
          :for={p <- @state.players}
          class="flex items-center justify-between rounded-xl border border-[#252A3A] bg-[#12141D] px-4 py-3"
        >
          <span class="font-bold">{p.username}</span>
          <span class={[
            "text-[11px] font-black uppercase tracking-wide",
            if(@state.ready[p.id], do: "text-[#C8FF2E]", else: "text-[#565D73]")
          ]}>
            {if @state.ready[p.id], do: "Ready", else: "Not ready"}
          </span>
        </li>
      </ul>

      <button
        :if={not @state.ready[@me]}
        phx-click="ready"
        class="mt-7 w-full rounded-xl bg-[#C8FF2E] px-4 py-4 text-base font-black uppercase tracking-wide text-[#0A0B10] hover:brightness-110"
      >
        I'm ready
      </button>
      <p :if={@state.ready[@me]} class="mt-7 text-sm text-[#8B91A7]">
        You're ready. The draft starts when everyone is.
      </p>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :me, :integer, required: true
  attr :search, :string, required: true

  defp board(assigns) do
    assigns =
      assign(assigns,
        my_turn?: assigns.state.current_picker_id == assigns.me,
        available: filter_players(assigns.state.available, assigns.search),
        names: names_by_id(assigns.state)
      )

    ~H"""
    <div class={[
      "mb-4 flex items-center justify-between gap-3 rounded-2xl border px-4 py-3",
      if(@my_turn?,
        do: "border-[#C8FF2E]/45 bg-[#C8FF2E]/10",
        else: "border-[#7C5CFF]/45 bg-[#7C5CFF]/10"
      )
    ]}>
      <div class="min-w-0">
        <p class={["hu-cond truncate text-xl uppercase tracking-wide", if(@my_turn?, do: "text-[#C8FF2E]", else: "text-[#9F8BFF]")]}>
          {if @my_turn?, do: "You're on the clock", else: "#{picker_name(@state)} is picking…"}
        </p>
        <p class="mt-0.5 text-[11px] font-bold uppercase tracking-wider text-[#8B91A7]">
          Pick {@state.pick_number} of {@state.total_picks}
        </p>
      </div>
      <div
        :if={@state.clock_deadline}
        id="pick-clock"
        phx-hook="PickClock"
        data-deadline={@state.clock_deadline}
        data-server-now={@state.server_now}
        class="flex-none rounded-xl border border-[#252A3A] bg-[#0A0B10] px-3 py-2 text-2xl font-black tabular-nums"
      >
        —
      </div>
    </div>

    <div class="mb-4 grid grid-cols-2 gap-3">
      <div :for={p <- @state.players} class="rounded-xl border border-[#1A1E2B] bg-[#12141D] p-3">
        <p class="mb-1.5 text-[11px] font-black uppercase tracking-wider text-[#8B91A7]">
          {if p.id == @me, do: "Your roster", else: p.username}
        </p>
        <ol class="space-y-1">
          <li :for={slot <- @state.slots} class="flex justify-between gap-2 text-sm">
            <span class="text-[#565D73]">{slot.label}</span>
            <span class="truncate text-right text-[#F4F5F7]">
              {roster_name(@names, @state, p.id, slot.key)}
            </span>
          </li>
        </ol>
      </div>
    </div>

    <form id="player-search" phx-change="search" class="mb-3">
      <input
        type="text"
        name="q"
        value={@search}
        placeholder="Search players"
        autocomplete="off"
        class="w-full rounded-xl border border-[#252A3A] bg-[#12141D] px-4 py-2.5 text-sm outline-none focus:border-[#C8FF2E]/60"
      />
    </form>

    <ul class="space-y-1.5">
      <li
        :for={player <- @available}
        class="flex items-center gap-3 rounded-xl border border-[#1A1E2B] bg-[#12141D] px-3 py-2.5"
      >
        <div class="min-w-0 flex-1">
          <p class="truncate font-bold">{player.name}</p>
          <p class="text-xs text-[#8B91A7]">
            {player.position} · {player.team}
            <span :if={player[:next_game_at]} class="text-[#565D73]">· {game_label(player.next_game_at)}</span>
            <span :if={player[:injury]} class={injury_class(player.injury)}>· {injury_label(player.injury)}</span>
          </p>
        </div>
        <span class="text-sm font-black text-[#C8FF2E]">{fmt(player.projection)}</span>
        <button
          phx-click="pick"
          phx-value-player-id={player.id}
          disabled={not @my_turn?}
          class="rounded-lg bg-[#C8FF2E] px-3 py-1.5 text-xs font-black uppercase text-[#0A0B10] disabled:cursor-not-allowed disabled:opacity-25"
        >
          Draft
        </button>
      </li>
    </ul>

    <p :if={@available == []} class="py-8 text-center text-sm text-[#565D73]">No players match that search.</p>
    """
  end

  defp filter_players(available, "") , do: Enum.take(available, 60)

  defp filter_players(available, q) do
    needle = String.downcase(q)

    available
    |> Enum.filter(&String.contains?(String.downcase(&1.name), needle))
    |> Enum.take(60)
  end

  defp picker_name(state) do
    case Enum.find(state.players, &(&1.id == state.current_picker_id)) do
      nil -> "Someone"
      p -> p.username
    end
  end

  # A roster slot holds a player_id; the name rides along on the pick. Drafted
  # players are gone from `available`, so picks are the only place to look.
  defp names_by_id(state) do
    Map.new(state.picks, fn pick -> {pick.player.id, pick.player.name} end)
  end

  defp roster_name(names, state, user_id, slot_key) do
    case get_in(state.rosters, [user_id, slot_key]) do
      nil -> "—"
      player_id -> Map.get(names, player_id, "—")
    end
  end

  defp injury_label(%{status: status}), do: status |> to_string() |> String.upcase()
  defp injury_label(%{"status" => status}), do: status |> to_string() |> String.upcase()
  defp injury_label(_), do: nil

  # OUT is a red flag, questionable an amber one — same split as the app.
  defp injury_class(%{status: :out}), do: "font-bold text-[#FF4557]"
  defp injury_class(%{"status" => "out"}), do: "font-bold text-[#FF4557]"
  defp injury_class(_), do: "font-bold text-[#FFB021]"

  # "7:00 PM ET" for today's ET day, "Tmw 7:05 PM ET" for tomorrow's — the
  # app's nextGameLabel, ported. ET is UTC-4 in season, same as everywhere.
  defp game_label(iso) when is_binary(iso) do
    normalized = Regex.replace(~r/T(\d{2}):(\d{2})Z$/, iso, "T\\1:\\2:00Z")

    case DateTime.from_iso8601(normalized) do
      {:ok, dt, _} ->
        et = DateTime.add(dt, -4 * 3600, :second)
        today = DateTime.utc_now() |> DateTime.add(-4 * 3600, :second) |> DateTime.to_date()
        prefix = if DateTime.to_date(et) == today, do: "", else: "Tmw "
        {h, m} = {et.hour, et.minute}
        {h12, ap} = cond do
          h == 0 -> {12, "AM"}
          h < 12 -> {h, "AM"}
          h == 12 -> {12, "PM"}
          true -> {h - 12, "PM"}
        end
        "#{prefix}#{h12}:#{String.pad_leading(to_string(m), 2, "0")} #{ap} ET"

      _ ->
        nil
    end
  end

  defp game_label(_), do: nil

  defp fmt(nil), do: "—"
  defp fmt(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp fmt(n), do: to_string(n)
end
