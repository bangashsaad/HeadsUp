defmodule HeadsUpWeb.DraftLive do
  @moduledoc """
  The draft room in the design's exact clothes: the VS board with photo slots
  and dashed placeholders, and the player-pool table with search, position
  pills and the condensed FPG column. Same engine as the phones — this
  LiveView subscribes to the draft GenServer's PubSub topic and sends picks
  through the same `Drafts.Server` calls, so a laptop and a phone can sit in
  one draft.
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
       |> assign(duel_id: duel_id, draft_id: draft.id, page_title: "Draft room")
       |> assign(state: Server.get_state(draft.id), search: "", pos: nil, bursts: [])}
    else
      _ ->
        {:ok, socket |> put_flash(:error, "That draft isn't yours to join.") |> redirect(to: "/app")}
    end
  end

  @impl true
  def handle_info({:draft_update, %{state: state}}, socket), do: {:noreply, assign(socket, state: state)}

  # A reaction — from a phone (channel broadcast!) or another browser. Both
  # arrive on the same topic as a %Phoenix.Socket.Broadcast{}.
  def handle_info(%Phoenix.Socket.Broadcast{event: "reaction", payload: %{emoji: emoji, user_id: uid}}, socket) do
    burst = %{id: System.unique_integer([:positive]), emoji: emoji, uid: uid}
    Process.send_after(self(), {:expire_burst, burst.id}, 2500)
    {:noreply, update(socket, :bursts, &Enum.take([burst | &1], 6))}
  end

  def handle_info({:expire_burst, id}, socket),
    do: {:noreply, update(socket, :bursts, &Enum.reject(&1, fn b -> b.id == id end))}

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

  @reaction_emojis ~w(🔥 😂 😭 🥶 💀 👑)

  def handle_event("react", %{"e" => emoji}, socket) when emoji in @reaction_emojis do
    HeadsUpWeb.Endpoint.broadcast(
      "draft:#{socket.assigns.duel_id}",
      "reaction",
      %{emoji: emoji, user_id: socket.assigns.current_user.id}
    )

    {:noreply, socket}
  end

  def handle_event("react", _params, socket), do: {:noreply, socket}

  def handle_event("search", %{"q" => q}, socket), do: {:noreply, assign(socket, search: q)}

  def handle_event("pos", %{"p" => ""}, socket), do: {:noreply, assign(socket, pos: nil)}
  def handle_event("pos", %{"p" => p}, socket), do: {:noreply, assign(socket, pos: p)}

  defp pick_error(:not_your_turn), do: "It's not your pick."
  defp pick_error(:already_drafted), do: "Someone just took that player."
  defp pick_error(:no_slot), do: "No open roster slot for that position."
  defp pick_error(other), do: "Couldn't make that pick (#{inspect(other)})."

  # --- render (the design's markup) -------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash} shell={assigns[:shell] || %{}}>
      <div style="flex:1;display:flex;flex-direction:column;gap:16px;max-width:1060px;width:100%;margin:0 auto;box-sizing:border-box;animation:huw-rise .3s ease">
        <%!-- header: title + turn pill / go-live / ready --%>
        <div style="display:flex;align-items:center;justify-content:space-between;gap:14px;flex-wrap:wrap">
          <div style="display:flex;flex-direction:column">
            <span class="hu-cond" style="font-size:24px;letter-spacing:.5px">
              DRAFT ROOM · VS {@state.players |> rivals(@current_user.id) |> Enum.map(&String.upcase(&1.username)) |> Enum.join(" + ")}
            </span>
            <span style="font-size:11.5px;color:#8B91A7;font-weight:600">
              {String.upcase(@state.sport)} · snake · {length(@state.slots)} slots · {@state.pick_clock_seconds}s clock · winner takes the rivalry lead
            </span>
          </div>

          <div :if={phase(@state) == :active} style={"display:flex;align-items:center;gap:10px;flex:none;white-space:nowrap;background:#{turn_bg(@state, @current_user.id)};border:1px solid #{turn_ink(@state, @current_user.id)};border-radius:999px;padding:9px 18px"}>
            <span class="huw-blink" style={"width:8px;height:8px;border-radius:4px;background:#{turn_ink(@state, @current_user.id)}"}></span>
            <span class="hu-cond" style={"font-size:17px;color:#{turn_ink(@state, @current_user.id)}"}>{turn_label(@state, @current_user.id)}</span>
            <span
              :if={@state.clock_deadline}
              id="pick-clock"
              phx-hook="PickClock"
              data-deadline={@state.clock_deadline}
              data-server-now={@state.server_now}
              class="hu-cond"
              style="font-size:17px"
            >
              —
            </span>
          </div>

          <.link
            :if={phase(@state) == :done}
            navigate={~p"/app/live/#{@duel_id}"}
            class="hu-cond huw-pulse"
            style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:16px;border-radius:999px;padding:10px 24px;white-space:nowrap"
          >
            DUEL SET · GO LIVE →
          </.link>

          <button
            :if={phase(@state) == :lobby and not @state.ready[@current_user.id]}
            phx-click="ready"
            class="hu-cond huw-pulse"
            style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:16px;border-radius:999px;padding:10px 24px;border:none;white-space:nowrap"
          >
            I'M READY →
          </button>
          <span
            :if={phase(@state) == :lobby and @state.ready[@current_user.id]}
            class="hu-cond"
            style="border:1px solid #252A3A;color:#8B91A7;font-size:15px;border-radius:999px;padding:10px 24px;white-space:nowrap"
          >
            WAITING ON {@state.players |> Enum.reject(&@state.ready[&1.id]) |> length()} …
          </span>
        </div>

        <%!-- the board: one column per seat --%>
        <div style="position:relative;border-radius:16px;border:1px solid #252A3A;background:#12141D;display:flex;flex-wrap:wrap">
          <.board_side state={@state} player={me(@state.players, @current_user.id)} mine={true} first={true} />
          <%= for rival <- rivals(@state.players, @current_user.id) do %>
            <div style="flex:none;display:flex;align-items:center;justify-content:center;padding:0 6px">
              <span class="hu-black" style="font-size:17px;color:transparent;-webkit-text-stroke:1px #3A4157">VS</span>
            </div>
            <.board_side state={@state} player={rival} mine={false} first={false} />
          <% end %>
        </div>

        <%!-- REACT (his bar) + the floating bursts --%>
        <div :if={phase(@state) == :active} style="display:flex;align-items:center;gap:8px;position:relative">
          <span style="font-size:9.5px;font-weight:900;letter-spacing:2px;color:#565D73">REACT</span>
          <button
            :for={e <- ~w(🔥 😂 😭 🥶 💀 👑)}
            phx-click="react"
            phx-value-e={e}
            style="cursor:pointer;width:34px;height:34px;border-radius:999px;border:1px solid #252A3A;background:#12141D;display:flex;align-items:center;justify-content:center;font-size:15px"
          >
            {e}
          </button>
          <span style="font-size:10px;font-weight:700;color:#565D73">
            {@state.players |> rivals(@current_user.id) |> Enum.map(& &1.username) |> List.first() || "They"} sees it instantly
          </span>
          <div style="position:absolute;right:0;top:-8px;display:flex;gap:6px;pointer-events:none">
            <span :for={b <- @bursts} class="huw-rise" style="font-size:22px">{b.emoji}</span>
          </div>
        </div>

        <%!-- the pool --%>
        <div :if={phase(@state) != :lobby} style="border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
          <div style="padding:12px 16px;border-bottom:1px solid #1A1E2B;display:flex;align-items:center;gap:12px;flex-wrap:wrap">
            <span style="font-size:11px;font-weight:900;letter-spacing:1.5px;color:#8B91A7;flex:none">PLAYER POOL</span>
            <form phx-change="search" id="pool-search" style="display:flex;align-items:center;gap:8px;background:#0D0F16;border:1px solid #252A3A;border-radius:999px;padding:8px 14px;flex:1;min-width:170px;max-width:280px">
              <span style="width:13px;height:13px;flex:none;background:#565D73;-webkit-mask:url('/icons/bd194911.svg') center/contain no-repeat;mask:url('/icons/bd194911.svg') center/contain no-repeat">
              </span>
              <input
                type="text"
                name="q"
                value={@search}
                autocomplete="off"
                placeholder="Search the pool…"
                style="flex:1;min-width:0;background:transparent;border:none;color:#F4F5F7;font-family:'Archivo',sans-serif;font-size:12.5px;outline:none"
              />
            </form>
            <div style="display:flex;gap:6px;flex-wrap:wrap">
              <button :for={p <- [nil | positions(@state)]} phx-click="pos" phx-value-p={p || ""} style={pos_pill(@pos == p)}>
                {p || "ALL"}
              </button>
            </div>
            <span style="margin-left:auto;font-size:10.5px;font-weight:800;color:#565D73;flex:none">
              PICK {@state.pick_number || "—"} OF {@state.total_picks}
            </span>
          </div>

          <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));max-height:460px;overflow:auto">
            <div
              :for={p <- pool(@state, @search, @pos)}
              phx-click={if my_turn?(@state, @current_user.id), do: "pick"}
              phx-value-player-id={p.id}
              style={"cursor:#{if my_turn?(@state, @current_user.id), do: "pointer", else: "default"};display:flex;align-items:center;gap:11px;padding:9px 16px;border-bottom:1px solid #14171F"}
            >
              <img
                :if={p[:headshot_url]}
                src={p.headshot_url}
                style="width:38px;height:38px;flex:none;border-radius:11px;object-fit:cover;object-position:top;background:#1A1E2B"
                alt=""
                loading="lazy"
              />
              <div
                :if={!p[:headshot_url]}
                style="width:38px;height:38px;flex:none;border-radius:11px;background:#1A1E2B;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:11px;color:#8B91A7"
              >
                {p.name |> String.slice(0, 2) |> String.upcase()}
              </div>
              <div style="display:flex;flex-direction:column;min-width:0">
                <span style="font-weight:700;font-size:13.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{p.name}</span>
                <span style="font-size:10.5px;color:#565D73;font-weight:700">{p.position} · {p.team}{game_suffix(p)}</span>
              </div>
              <div style="margin-left:auto;display:flex;align-items:center;gap:12px">
                <span class="hu-cond" style="font-size:20px;color:#C7CBD9">{proj(p.projection)}</span>
                <span :if={tag(p)} style={"font-size:10px;font-weight:900;letter-spacing:1px;color:#{tag_ink(p)}"}>{tag(p)}</span>
              </div>
            </div>
          </div>
          <div :if={pool(@state, @search, @pos) == []} style="padding:26px;text-align:center;font-size:12px;color:#565D73;font-weight:600">
            No players match — clear the search or position filter.
          </div>
        </div>

        <%!-- lobby: who's in --%>
        <div :if={phase(@state) == :lobby} style="border-radius:16px;border:1px solid #252A3A;background:#12141D;padding:18px;display:flex;gap:10px;flex-wrap:wrap">
          <div
            :for={p <- @state.players}
            style={"display:flex;align-items:center;gap:9px;border:1px solid #{if @state.ready[p.id], do: "rgba(200,255,46,.4)", else: "#252A3A"};background:#{if @state.ready[p.id], do: "rgba(200,255,46,.06)", else: "transparent"};border-radius:999px;padding:8px 16px"}
          >
            <span style="font-weight:800;font-size:13px">{p.username}</span>
            <span style={"font-size:10px;font-weight:900;letter-spacing:1px;color:#{if @state.ready[p.id], do: "#C8FF2E", else: "#565D73"}"}>
              {if @state.ready[p.id], do: "READY", else: "NOT READY"}
            </span>
          </div>
        </div>
      </div>
    </Layouts.shell>
    """
  end

  attr :state, :map, required: true
  attr :player, :map, required: true
  attr :mine, :boolean, required: true
  attr :first, :boolean, required: true

  defp board_side(assigns) do
    ~H"""
    <div style={"flex:1;min-width:min(250px,100%);padding:14px 18px;display:flex;flex-direction:column;gap:11px#{if !@first, do: ";border-left:1px solid #1A1E2B"}"}>
      <div style="display:flex;align-items:baseline;justify-content:space-between">
        <span style={"font-size:11px;font-weight:900;letter-spacing:1.5px;color:#{if @mine, do: "var(--acc,#C8FF2E)", else: "#FF4557"}"}>
          {if @mine, do: "YOU", else: String.upcase(@player.username)}
        </span>
        <span style="font-size:10.5px;font-weight:800;color:#565D73">
          {filled_count(@state, @player.id)}/{length(@state.slots)}
        </span>
      </div>
      <div style="display:flex;gap:7px;flex-wrap:wrap">
        <div :for={slot <- @state.slots} style="width:44px;display:flex;flex-direction:column;align-items:center;gap:4px">
          <%= case slot_pick(@state, @player.id, slot.key) do %>
            <% nil -> %>
              <div style="width:42px;height:42px;border-radius:12px;border:1px dashed #3A4157;display:flex;align-items:center;justify-content:center">
                <span style="font-size:9.5px;font-weight:800;color:#565D73">{slot.key |> String.slice(0, 3)}</span>
              </div>
            <% player -> %>
              <img
                :if={player[:headshot_url]}
                src={player.headshot_url}
                style={"width:42px;height:42px;border-radius:12px;object-fit:cover;object-position:top;background:#1A1E2B;border:1px solid #{if @mine, do: "rgba(200,255,46,.45)", else: "rgba(255,69,87,.45)"}"}
                alt=""
              />
              <div
                :if={!player[:headshot_url]}
                style={"width:42px;height:42px;border-radius:12px;background:#1A1E2B;border:1px solid #{if @mine, do: "rgba(200,255,46,.45)", else: "rgba(255,69,87,.45)"};display:flex;align-items:center;justify-content:center;font-weight:800;font-size:11px;color:#C7CBD9"}
              >
                {player.name |> String.slice(0, 2) |> String.upcase()}
              </div>
              <span style="font-size:9px;font-weight:700;color:#C7CBD9;max-width:44px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">
                {last_name(player.name)}
              </span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # --- state helpers ----------------------------------------------------------

  defp phase(%{phase: p}) when p in [:lobby, "lobby"], do: :lobby
  defp phase(%{phase: p}) when p in [:done, "done", :complete, "complete"], do: :done
  defp phase(_), do: :active

  defp me(players, my_id), do: Enum.find(players, &(&1.id == my_id)) || %{id: my_id, username: "you"}
  defp rivals(players, my_id), do: Enum.reject(players, &(&1.id == my_id))

  defp my_turn?(state, my_id), do: state.current_picker_id == my_id

  defp turn_label(state, my_id) do
    if my_turn?(state, my_id) do
      "YOUR PICK"
    else
      case Enum.find(state.players, &(&1.id == state.current_picker_id)) do
        nil -> "PICKING…"
        p -> "#{String.upcase(p.username)} PICKING"
      end
    end
  end

  defp turn_ink(state, my_id), do: if(my_turn?(state, my_id), do: "var(--acc,#C8FF2E)", else: "#9F8BFF")
  defp turn_bg(state, my_id), do: if(my_turn?(state, my_id), do: "rgba(200,255,46,.1)", else: "rgba(124,92,255,.12)")

  defp pos_pill(true),
    do:
      "cursor:pointer;border:1px solid var(--acc,#C8FF2E);background:rgba(200,255,46,.1);color:var(--acc,#C8FF2E);font-size:11px;font-weight:800;letter-spacing:.5px;border-radius:999px;padding:6px 14px;white-space:nowrap"

  defp pos_pill(false),
    do:
      "cursor:pointer;border:1px solid #252A3A;background:transparent;color:#8B91A7;font-size:11px;font-weight:800;letter-spacing:.5px;border-radius:999px;padding:6px 14px;white-space:nowrap"

  # A roster slot holds a player_id; the full player rides on the pick.
  defp slot_pick(state, user_id, slot_key) do
    case get_in(state.rosters, [user_id, slot_key]) do
      nil -> nil
      player_id -> Enum.find_value(state.picks, fn pk -> if pk.player.id == player_id, do: pk.player end)
    end
  end

  defp filled_count(state, user_id), do: map_size(Map.get(state.rosters, user_id, %{}))

  defp positions(state) do
    state.slots |> Enum.flat_map(& &1.eligible) |> Enum.uniq() |> Enum.sort()
  end

  defp pool(state, search, pos) do
    needle = String.downcase(search)

    state.available
    |> Enum.filter(fn p ->
      (search == "" or String.contains?(String.downcase(p.name), needle)) and
        (pos == nil or p.position == pos)
    end)
    |> Enum.take(60)
  end

  defp proj(nil), do: "—"
  defp proj(n) when is_float(n), do: :erlang.float_to_binary(n, decimals: 1)
  defp proj(n), do: to_string(n)

  defp game_suffix(p) do
    case p[:next_game_at] do
      nil -> ""
      iso -> " · #{game_label(iso)}"
    end
  end

  defp tag(p) do
    case p[:injury] do
      %{status: :out} -> "OUT"
      %{"status" => "out"} -> "OUT"
      %{status: :questionable} -> "GTD"
      %{"status" => "questionable"} -> "GTD"
      _ -> nil
    end
  end

  defp tag_ink(p), do: if(tag(p) == "OUT", do: "#FF4557", else: "#FFB021")

  defp last_name(name), do: name |> String.split() |> List.last()

  defp game_label(iso) when is_binary(iso) do
    normalized = Regex.replace(~r/T(\d{2}):(\d{2})Z$/, iso, "T\\1:\\2:00Z")

    case DateTime.from_iso8601(normalized) do
      {:ok, dt, _} ->
        et = DateTime.add(dt, -4 * 3600, :second)
        today = DateTime.utc_now() |> DateTime.add(-4 * 3600, :second) |> DateTime.to_date()
        prefix = if DateTime.to_date(et) == today, do: "", else: "Tmw "

        {h12, ap} =
          cond do
            et.hour == 0 -> {12, "AM"}
            et.hour < 12 -> {et.hour, "AM"}
            et.hour == 12 -> {12, "PM"}
            true -> {et.hour - 12, "PM"}
          end

        "#{prefix}#{h12}:#{String.pad_leading(to_string(et.minute), 2, "0")} #{ap} ET"

      _ ->
        nil
    end
  end

  defp game_label(_), do: nil
end
