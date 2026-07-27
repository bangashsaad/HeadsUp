defmodule HeadsUpWeb.DraftChannel do
  @moduledoc """
  Realtime transport for one live draft, topic `"draft:<duel_id>"` (the duel id
  the mobile app already holds). Thin by design: it authorizes the join (only
  the two participants), resolves the duel to its draft + ensures the engine
  process is alive, then forwards client intents to `HeadsUp.Drafts.Server` and
  relays the engine's PubSub broadcasts to both phones.

  The engine broadcasts a full snapshot on every change, so every server->client
  message is the same `"update"` event carrying `%{event, state, meta}`; the
  client just replaces its state and uses `event` for transient UI cues. The
  join reply is itself a snapshot, which makes reconnect a no-op (no replay).
  """
  use HeadsUpWeb, :channel

  alias HeadsUp.{Contests, Drafts}
  alias HeadsUp.Drafts.{Server, Supervisor}

  @impl true
  def join("draft:" <> duel_id_str, _params, socket) do
    uid = socket.assigns.current_user_id

    with {duel_id, ""} <- Integer.parse(duel_id_str),
         %Contests.Duel{} = duel <- Contests.get_duel_for_draft(uid, duel_id),
         {:ok, draft} <- Drafts.get_or_create_draft_for_duel(duel),
         {:ok, _pid} <- Supervisor.ensure_started(draft.id, duel) do
      socket = assign(socket, %{duel_id: duel_id, draft_id: draft.id, current_user_id: uid})
      send(self(), :after_join)
      {:ok, %{state: Server.get_state(draft.id)}, socket}
    else
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Rejoining cancels any disconnect grace timer for this user.
    Server.reconnected(socket.assigns.draft_id, socket.assigns.current_user_id)
    {:noreply, socket}
  end

  # Engine PubSub broadcast (same topic on HeadsUp.PubSub) -> push to this client.
  def handle_info({:draft_update, payload}, socket) do
    push(socket, "update", payload)
    {:noreply, socket}
  end

  # --- client -> server intents ---

  @impl true
  def handle_in("ready", _payload, socket) do
    socket.assigns.draft_id
    |> Server.ready(socket.assigns.current_user_id)
    |> ack(socket)
  end

  def handle_in("make_pick", %{"player_id" => player_id}, socket) do
    socket.assigns.draft_id
    |> Server.make_pick(socket.assigns.current_user_id, player_id)
    |> ack(socket)
  end

  def handle_in("set_queue", %{"player_ids" => ids}, socket) when is_list(ids) do
    Server.set_queue(socket.assigns.draft_id, socket.assigns.current_user_id, ids)
    {:reply, :ok, socket}
  end

  def handle_in("cancel", _payload, socket) do
    socket.assigns.draft_id
    |> Server.cancel(socket.assigns.current_user_id)
    |> ack(socket)
  end

  def handle_in("request_state", _payload, socket) do
    {:reply, {:ok, %{state: Server.get_state(socket.assigns.draft_id)}}, socket}
  end

  # Ephemeral trash talk: relay a reaction to everyone in the room (sender
  # included — their burst renders off the broadcast too, so all phones agree).
  # Never touches the engine, never persists. Unknown emojis are dropped.
  @reaction_emojis ~w(🔥 😂 😭 🥶 💀 👑)
  def handle_in("react", %{"emoji" => emoji}, socket) when emoji in @reaction_emojis do
    broadcast!(socket, "reaction", %{emoji: emoji, user_id: socket.assigns.current_user_id})
    {:noreply, socket}
  end

  def handle_in("react", _payload, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    case socket.assigns do
      %{draft_id: draft_id, current_user_id: uid} -> Server.disconnected(draft_id, uid)
      _ -> :ok
    end

    :ok
  end

  # Engine returns the full state on success (already broadcast to both), or
  # {:error, reason}; the acting client gets a thin ack / the error reason.
  defp ack({:error, reason}, socket), do: {:reply, {:error, %{reason: to_string(reason)}}, socket}
  defp ack(_state, socket), do: {:reply, :ok, socket}
end
