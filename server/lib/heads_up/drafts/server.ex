defmodule HeadsUp.Drafts.Server do
  @moduledoc """
  One GenServer per live draft — the single source of truth for live draft
  state. Drives the lobby -> coin-flip -> active -> complete lifecycle, the
  2-player snake order, the per-pick clock, and position-aware auto-pick on
  timeout. Every pick is written through to Postgres (`Drafts.record_pick/1`)
  so a crash can rebuild state by replaying picks on init.

  Registered by `draft_id` in `HeadsUp.Drafts.Registry`; broadcasts every state
  change over PubSub topic `"draft:<duel_id>"` (the id the mobile app holds), so
  the channel can fan out to both phones.

  RNG (coin flip) and the clock's `now` source are injectable via start opts so
  tests are fully deterministic.
  """
  use GenServer, restart: :transient

  require Logger

  alias HeadsUp.Drafts
  alias HeadsUp.Drafts.{AutoPick, Lineup, PoolFilter}

  @pubsub HeadsUp.PubSub

  # --- public API ---------------------------------------------------------

  def start_link(opts) do
    draft_id = Keyword.fetch!(opts, :draft_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(draft_id))
  end

  def via_tuple(draft_id), do: {:via, Registry, {HeadsUp.Drafts.Registry, draft_id}}

  @doc "Current public state, or `{:error, :not_found}` if no server is running."
  def get_state(draft_id), do: safe_call(draft_id, :get_state)

  @doc "Mark a user ready in the lobby. When both are ready the coin flip fires and the draft starts."
  def ready(draft_id, user_id), do: safe_call(draft_id, {:ready, user_id})

  @doc "Make a manual pick. Errors: :not_your_turn | :unavailable | :no_open_slot | :not_active."
  def make_pick(draft_id, user_id, player_id),
    do: safe_call(draft_id, {:make_pick, user_id, player_id})

  @doc "Set a user's private auto-pick queue (ordered player_ids). Auto-pick prefers it."
  def set_queue(draft_id, user_id, player_ids),
    do: safe_call(draft_id, {:set_queue, user_id, player_ids})

  @doc "Tell the draft a user's socket dropped; shrinks their clock to a 60s grace window."
  def disconnected(draft_id, user_id) do
    GenServer.cast(via_tuple(draft_id), {:disconnected, user_id})
  end

  @doc "Tell the draft a user reconnected; restores the full pick clock if it's their turn."
  def reconnected(draft_id, user_id) do
    GenServer.cast(via_tuple(draft_id), {:reconnected, user_id})
  end

  @doc "A participant cancels the draft (e.g. a no-show in the lobby). No forfeit win."
  def cancel(draft_id, user_id), do: safe_call(draft_id, {:cancel, user_id})

  defp safe_call(draft_id, msg) do
    GenServer.call(via_tuple(draft_id), msg)
  catch
    :exit, _ -> {:error, :not_found}
  end

  # --- init / crash recovery ---------------------------------------------

  @impl true
  def init(opts) do
    duel = Keyword.fetch!(opts, :duel)
    draft_id = Keyword.fetch!(opts, :draft_id)
    rng = Keyword.get(opts, :rng, &:rand.uniform/1)
    now_fun = Keyword.get(opts, :now_fun, &DateTime.utc_now/0)
    clock_override = Keyword.get(opts, :pick_clock_seconds)

    slots = Lineup.slots(duel.lineup_template)

    # Who's playing, in seat order: [challenger, opponent] for 1v1, every
    # accepted seat for a group duel. All per-user maps key off this list.
    players = HeadsUp.Contests.draft_players(duel)
    player_ids = Enum.map(players, & &1.id)

    state = %{
      draft_id: draft_id,
      duel_id: duel.id,
      sport: duel.sport,
      lineup_template: duel.lineup_template,
      slots: slots,
      pick_clock_seconds: clock_override || duel.pick_clock_seconds,
      players: players,
      player_ids: player_ids,
      phase: :lobby,
      ready: Map.new(player_ids, &{&1, false}),
      # liveness is a per-user socket REFCOUNT (a user may briefly hold two
      # sockets across a reconnect); grace only fires when it drops to 0.
      connected: Map.new(player_ids, &{&1, 0}),
      first_picker_id: nil,
      pick_order: [],
      pick_number: nil,
      total_picks: length(slots) * length(player_ids),
      current_picker_id: nil,
      available: draftable_pool(duel.sport, slots, length(player_ids)),
      rosters: Map.new(player_ids, &{&1, %{}}),
      # Per-user priority queue of player_ids (client-authoritative, in-memory);
      # auto-pick prefers it. Never broadcast — it's each player's private plan.
      queue: Map.new(player_ids, &{&1, []}),
      picks: [],
      timer_ref: nil,
      deadline: nil,
      clock_owner_pick: nil,
      rng: rng,
      now_fun: now_fun
    }

    {:ok, state, {:continue, :replay}}
  end

  @impl true
  def handle_continue(:replay, state) do
    draft = Drafts.get_draft(state.draft_id)
    picks = Drafts.replay(state.draft_id)

    state =
      cond do
        draft == nil ->
          state

        picks == [] and draft.status == "active" ->
          # readied + order drawn but no picks yet: resume the first pick.
          state |> resume_order(draft) |> set_active_pick(1) |> arm_clock()

        picks == [] ->
          state

        true ->
          state
          |> resume_order(draft)
          |> replay_picks(picks)
          |> finish_or_resume(draft.status)
      end

    broadcast(state, "replay")
    {:noreply, state}
  end

  # Rebuild the snake from the persisted round-1 order; legacy 2-player rows
  # (no pick_order) derive it from first_picker_id + the other player.
  defp resume_order(state, draft) do
    base =
      case draft.pick_order do
        [_ | _] = base -> base
        _ when not is_nil(draft.first_picker_id) -> [draft.first_picker_id | state.player_ids -- [draft.first_picker_id]]
        _ -> nil
      end

    if base do
      order = Drafts.snake_order(base, length(state.slots))
      %{state | phase: :active, first_picker_id: List.first(base), pick_order: order}
    else
      state
    end
  end

  defp replay_picks(state, picks) do
    Enum.reduce(picks, state, fn p, acc ->
      player = acc.available[p.player_id]

      acc
      |> put_in([:rosters, p.user_id, p.slot], p.player_id)
      |> update_in([:available], &Map.delete(&1, p.player_id))
      |> Map.update!(:picks, &(&1 ++ [pick_view(p, player)]))
      |> Map.put(:pick_number, p.pick_number + 1)
    end)
  end

  defp finish_or_resume(state, status) do
    cond do
      status == "complete" ->
        %{state | phase: :complete, current_picker_id: nil}

      state.pick_number > state.total_picks ->
        # Crashed after the final pick persisted but before completion committed:
        # heal the durable side so the duel doesn't stay stuck in "drafting".
        {:ok, _} = Drafts.complete_draft(state.draft_id)
        %{state | phase: :complete, current_picker_id: nil}

      true ->
        state |> set_active_pick(state.pick_number) |> arm_clock()
    end
  end

  # Only players at positions some slot can hold are draftable, so undraftable
  # seed entries (e.g. NFL kickers with no K slot) never clutter the board or
  # leave the auto-pick with dead choices. Players with no upcoming game today
  # or tomorrow are dropped too (they can't score this window), and everyone
  # kept is annotated with :next_game_at so the board shows WHEN they play —
  # unless filtering would gut the board (a full pool beats an undraftable one).
  # "Gut" scales with the table: N players need N rosters + slack.
  defp draftable_pool(sport, slots, nplayers) do
    eligible = slots |> Enum.flat_map(& &1.eligible) |> MapSet.new()
    pool = sport |> Drafts.draft_pool() |> Map.filter(fn {_id, p} -> p.position in eligible end)

    case PoolFilter.scan(sport) do
      %{ok: true, next_game_at: next} ->
        filtered = Map.filter(pool, fn {_id, p} -> Map.has_key?(next, p.team) end)

        if map_size(filtered) >= length(slots) * nplayers * 2 do
          annotate(filtered, next)
        else
          annotate(pool, next)
        end

      %{ok: false} ->
        pool
    end
  end

  defp annotate(pool, next_game_at) do
    Map.new(pool, fn {id, p} -> {id, Map.put(p, :next_game_at, Map.get(next_game_at, p.team))} end)
  end

  # --- calls --------------------------------------------------------------

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, public_state(state), state}

  def handle_call({:ready, uid}, _from, %{phase: :lobby} = state) do
    state = if Map.has_key?(state.ready, uid), do: put_in(state.ready[uid], true), else: state

    if Enum.all?(state.player_ids, &state.ready[&1]) do
      state = start_draft(state)
      {:reply, public_state(state), state}
    else
      broadcast(state, "ready")
      {:reply, public_state(state), state}
    end
  end

  def handle_call({:ready, _uid}, _from, state) do
    # already past the lobby — no-op, just echo state
    {:reply, public_state(state), state}
  end

  def handle_call({:make_pick, uid, player_id}, _from, %{phase: :active} = state) do
    with :ok <- ensure_turn(state, uid),
         {:ok, player} <- ensure_available(state, player_id),
         {:ok, slot_key} <- ensure_open_slot(state, uid, player) do
      state = commit_pick(state, uid, player_id, slot_key, false)
      {:reply, public_state(state), state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:make_pick, _uid, _pid}, _from, state),
    do: {:reply, {:error, :not_active}, state}

  def handle_call({:set_queue, uid, ids}, _from, state) do
    if Map.has_key?(state.queue, uid) do
      {:reply, :ok, put_in(state.queue[uid], Enum.filter(List.wrap(ids), &is_integer/1))}
    else
      {:reply, {:error, :not_a_participant}, state}
    end
  end

  def handle_call({:cancel, uid}, _from, %{phase: phase} = state) when phase in [:lobby, :active] do
    {:ok, _} = Drafts.cancel_draft(state.draft_id)
    state = %{state | phase: :cancelled, current_picker_id: nil} |> cancel_clock()
    {:reply, public_state(state), tap_broadcast(state, "cancelled", %{by: uid})}
  end

  def handle_call({:cancel, _uid}, _from, state),
    do: {:reply, {:error, :not_cancellable}, state}

  # --- clock timeout ------------------------------------------------------

  @impl true
  def handle_info({:clock_expired, pick_no}, %{phase: :active, clock_owner_pick: pick_no} = state) do
    uid = state.current_picker_id

    case AutoPick.pick(state.available, Map.keys(state.rosters[uid]), state.slots, Map.get(state.queue, uid, [])) do
      {:ok, player_id, slot_key} ->
        {:noreply, commit_pick(state, uid, player_id, slot_key, true)}

      :error ->
        # Fail safe rather than hang: end the draft with the partial rosters
        # (empty slots simply score 0 in Phase 5, the locked draft-risk rule).
        Logger.error("draft #{state.draft_id}: auto-pick found no eligible player — finalizing draft")
        {:noreply, finalize_complete(cancel_clock(state))}
    end
  end

  # stale timer (a pick already happened): ignore
  def handle_info({:clock_expired, _stale}, state), do: {:noreply, state}

  # --- disconnect / reconnect (60s grace) ---------------------------------

  @impl true
  def handle_cast({:disconnected, uid}, state) do
    state = update_in(state.connected[uid], &max(&1 - 1, 0))

    # Only shrink to the 60s grace once the user's LAST socket has dropped, and
    # only for LIVE clocks — an async (multi-hour) clock must not collapse to 60s
    # just because the picker backgrounded the app.
    state =
      if state.connected[uid] == 0 and state.phase == :active and
           state.current_picker_id == uid and live_clock?(state) do
        shrink_clock(state, 60)
      else
        state
      end

    broadcast(state, "disconnected", %{user_id: uid})
    {:noreply, state}
  end

  def handle_cast({:reconnected, uid}, state) do
    was_off = state.connected[uid] == 0
    state = update_in(state.connected[uid], &(&1 + 1))

    state =
      if was_off and state.phase == :active and state.current_picker_id == uid do
        arm_clock(state)
      else
        state
      end

    broadcast(state, "reconnected", %{user_id: uid})
    {:noreply, state}
  end

  defp live_clock?(state), do: state.pick_clock_seconds <= 90

  # --- lifecycle helpers --------------------------------------------------

  defp start_draft(state) do
    base = Drafts.randomize_order(state.player_ids, state.rng)
    draft = Drafts.get_draft(state.draft_id)
    {:ok, draft} = Drafts.start_active(draft, base)

    state
    |> resume_order(draft)
    |> set_active_pick(1)
    |> arm_clock()
    |> tap_broadcast("coin_flip", %{first_picker_id: List.first(base), order: base})
  end

  defp set_active_pick(state, pick_number) do
    %{
      state
      | phase: :active,
        pick_number: pick_number,
        current_picker_id: Drafts.picker_for(state.pick_order, pick_number)
    }
  end

  # End the draft early (pool exhausted): persist completion, keep partial rosters.
  defp finalize_complete(state) do
    {:ok, _} = Drafts.complete_draft(state.draft_id)

    %{state | phase: :complete, current_picker_id: nil}
    |> tap_broadcast("draft_complete", %{reason: "pool_exhausted"})
  end

  defp commit_pick(state, uid, player_id, slot_key, auto?) do
    {:ok, _pick} =
      Drafts.record_pick(%{
        draft_id: state.draft_id,
        pick_number: state.pick_number,
        user_id: uid,
        player_id: player_id,
        slot: slot_key,
        auto_picked: auto?
      })

    player = state.available[player_id]

    state =
      state
      |> put_in([:rosters, uid, slot_key], player_id)
      |> update_in([:available], &Map.delete(&1, player_id))
      |> Map.update!(:picks, &(&1 ++ [pick_view(%{pick_number: state.pick_number, slot: slot_key, auto_picked: auto?, user_id: uid}, player)]))
      |> cancel_clock()

    next = state.pick_number + 1

    if next > state.total_picks do
      {:ok, _} = Drafts.complete_draft(state.draft_id)

      %{state | phase: :complete, current_picker_id: nil, pick_number: next}
      |> tap_broadcast("pick_made", %{pick_number: state.pick_number, user_id: uid})
      |> tap_broadcast("draft_complete", %{})
    else
      state
      |> set_active_pick(next)
      |> arm_clock()
      |> tap_notify_turn()
      |> tap_broadcast("pick_made", %{pick_number: next - 1, user_id: uid})
    end
  end

  # Push "your pick" ONLY when the picker has no live socket in the room —
  # players watching the draft see the turn instantly; a push would be noise.
  # This is what makes long-clock async drafts work: pick, walk away, get pinged.
  defp tap_notify_turn(state) do
    uid = state.current_picker_id

    if Map.get(state.connected, uid, 0) == 0 do
      HeadsUp.Notifications.notify_user(
        uid,
        "You're on the clock ⏱️",
        "It's your pick (#{state.pick_number}/#{state.total_picks}) in your live draft.",
        %{type: "draft", duel_id: state.duel_id}
      )
    end

    state
  end

  # --- pick validation ----------------------------------------------------

  defp ensure_turn(%{current_picker_id: uid}, uid), do: :ok
  defp ensure_turn(_state, _uid), do: {:error, :not_your_turn}

  defp ensure_available(state, player_id) do
    case Map.get(state.available, player_id) do
      nil -> {:error, :unavailable}
      player -> {:ok, player}
    end
  end

  defp ensure_open_slot(state, uid, player) do
    case Lineup.can_fill?(state.slots, Map.keys(state.rosters[uid]), player.position) do
      {:ok, slot_key} -> {:ok, slot_key}
      :error -> {:error, :no_open_slot}
    end
  end

  # --- clock --------------------------------------------------------------

  defp arm_clock(state), do: arm_clock(state, state.pick_clock_seconds)

  defp arm_clock(state, seconds) do
    state = cancel_clock(state)
    ref = Process.send_after(self(), {:clock_expired, state.pick_number}, seconds * 1000)
    deadline = DateTime.add(state.now_fun.(), seconds, :second)
    %{state | timer_ref: ref, deadline: deadline, clock_owner_pick: state.pick_number}
  end

  # Shrink the current clock to at most `max_seconds` (the disconnect grace).
  # Never grows it; same {:clock_expired} path auto-picks on expiry.
  defp shrink_clock(state, max_seconds) do
    remaining =
      if state.deadline, do: DateTime.diff(state.deadline, state.now_fun.(), :second), else: 0

    if remaining > max_seconds, do: arm_clock(state, max_seconds), else: state
  end

  defp cancel_clock(%{timer_ref: nil} = state), do: state

  defp cancel_clock(state) do
    Process.cancel_timer(state.timer_ref)
    %{state | timer_ref: nil, deadline: nil, clock_owner_pick: nil}
  end

  # --- broadcast / rendering ---------------------------------------------

  defp tap_broadcast(state, event, meta) do
    broadcast(state, event, meta)
    state
  end

  defp broadcast(state, event, meta \\ %{}) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "draft:#{state.duel_id}",
      {:draft_update, %{event: event, state: public_state(state), meta: meta}}
    )
  end

  @doc false
  def public_state(state) do
    %{
      draft_id: state.draft_id,
      duel_id: state.duel_id,
      sport: state.sport,
      lineup_template: state.lineup_template,
      phase: state.phase,
      # Seat-ordered players so the client can render any table size.
      players: state.players,
      ready: state.ready,
      connected: Map.new(state.connected, fn {uid, n} -> {uid, n > 0} end),
      first_picker_id: state.first_picker_id,
      # The full snake sequence (empty until the order is drawn).
      pick_order: state.pick_order,
      current_picker_id: state.current_picker_id,
      pick_number: state.pick_number,
      total_picks: state.total_picks,
      pick_clock_seconds: state.pick_clock_seconds,
      clock_deadline: state.deadline && DateTime.to_iso8601(state.deadline),
      server_now: DateTime.to_iso8601(state.now_fun.()),
      slots: state.slots,
      rosters: render_rosters(state),
      picks: state.picks,
      available: render_available(state)
    }
  end

  defp render_rosters(state) do
    Map.new(state.rosters, fn {uid, slot_map} -> {uid, slot_map} end)
  end

  defp render_available(state) do
    state.available
    |> Map.values()
    |> Enum.sort_by(fn p -> {-p.projection, p.id} end)
  end

  defp pick_view(p, player) do
    %{
      pick_number: p.pick_number,
      user_id: p.user_id,
      slot: p.slot,
      auto_picked: p.auto_picked,
      player: player
    }
  end
end
