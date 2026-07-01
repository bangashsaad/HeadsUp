defmodule HeadsUp.Drafts.ServerTest do
  # async: false -> DataCase puts the sandbox in shared mode so the separately
  # supervised draft GenServer can use the test's DB connection.
  use HeadsUp.DataCase, async: false

  alias HeadsUp.{Accounts, Drafts, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Drafts.Server
  alias HeadsUp.Sports.Player

  @fixed ~U[2026-06-26 12:00:00Z]

  setup do
    challenger = user("chal")
    opponent = user("oppo")
    duel = accepted_duel(challenger, opponent)
    {:ok, draft} = Drafts.get_or_create_draft_for_duel(duel)
    pool()

    %{challenger: challenger, opponent: opponent, duel: duel, draft: draft}
  end

  # challenger-first coin flip (rng returns 1). Unique child id so a single test
  # can start more than one server (e.g. the crash-recovery restart).
  defp start(draft, duel, opts \\ []) do
    opts = Keyword.merge([draft_id: draft.id, duel: duel, rng: fn 2 -> 1 end], opts)
    spec = Supervisor.child_spec({Server, opts}, id: {Server, System.unique_integer([:positive])})
    start_supervised!(spec)
  end

  describe "lobby -> ready-check -> coin flip" do
    test "stays in lobby until both ready, then starts active with snake order", ctx do
      pid = start(ctx.draft, ctx.duel)
      assert Server.get_state(ctx.draft.id).phase == :lobby

      assert Server.ready(ctx.draft.id, ctx.challenger.id).phase == :lobby
      state = Server.ready(ctx.draft.id, ctx.opponent.id)

      assert state.phase == :active
      assert state.first_picker_id == ctx.challenger.id
      assert state.current_picker_id == ctx.challenger.id
      assert state.pick_number == 1
      assert state.clock_deadline != nil
      # duel flipped accepted -> drafting
      assert Repo.get(Duel, ctx.duel.id).status == "drafting"
      assert is_pid(pid)
    end
  end

  describe "manual picks" do
    setup ctx do
      start(ctx.draft, ctx.duel)
      Server.ready(ctx.draft.id, ctx.challenger.id)
      Server.ready(ctx.draft.id, ctx.opponent.id)
      :ok
    end

    test "advance the snake and assign the right slot", ctx do
      pg = player_at("PG", 0)
      state = Server.make_pick(ctx.draft.id, ctx.challenger.id, pg.id)

      assert state.pick_number == 2
      assert state.current_picker_id == ctx.opponent.id
      # wnba_standard is now coarse G/F/C — a PG fills the first guard slot.
      assert state.rosters[ctx.challenger.id] == %{"G1" => pg.id}
      refute Enum.any?(state.available, &(&1.id == pg.id))
    end

    test "reject picks out of turn and unavailable players", ctx do
      pg = player_at("PG", 0)
      assert Server.make_pick(ctx.draft.id, ctx.opponent.id, pg.id) == {:error, :not_your_turn}

      # challenger drafts pg; opponent then can't take the same player
      Server.make_pick(ctx.draft.id, ctx.challenger.id, pg.id)
      assert Server.make_pick(ctx.draft.id, ctx.opponent.id, pg.id) == {:error, :unavailable}
    end
  end

  describe "auto-pick on clock expiry" do
    setup ctx do
      pid = start(ctx.draft, ctx.duel)
      Server.ready(ctx.draft.id, ctx.challenger.id)
      Server.ready(ctx.draft.id, ctx.opponent.id)
      %{pid: pid}
    end

    test "takes the highest-projection eligible player and marks it auto", ctx do
      state = expire(ctx.pid, ctx.draft.id)

      assert state.pick_number == 2
      [pick] = state.picks
      assert pick.auto_picked == true
      # highest-projection player overall is a PG -> fills the first guard slot
      assert pick.slot == "G1"
      assert pick.player.position == "PG"
    end

    test "auto-pick honors the picker's queue over projection", ctx do
      picker = Server.get_state(ctx.draft.id).current_picker_id
      # a specific guard that is NOT the top-projection player overall
      target = player_at("SG", 0)
      assert :ok = Server.set_queue(ctx.draft.id, picker, [target.id])

      state = expire(ctx.pid, ctx.draft.id)

      [pick] = state.picks
      assert pick.player.id == target.id
      assert pick.auto_picked
    end

    test "a stale clock_expired (for an already-made pick) is ignored", ctx do
      # make pick 1 manually -> now on pick 2, clock owner = 2
      Server.make_pick(ctx.draft.id, ctx.challenger.id, player_at("PG", 0).id)
      before = Server.get_state(ctx.draft.id)
      assert before.pick_number == 2

      send(ctx.pid, {:clock_expired, 1})
      after_state = Server.get_state(ctx.draft.id)
      assert after_state.pick_number == 2
      assert length(after_state.picks) == 1
    end

    test "running the clock out for every pick completes the draft", ctx do
      final =
        Enum.reduce(1..10, nil, fn _, _ -> expire(ctx.pid, ctx.draft.id) end)

      assert final.phase == :complete
      assert final.current_picker_id == nil
      assert length(final.picks) == 10
      assert Repo.get(Duel, ctx.duel.id).status == "drafted"
      assert Drafts.get_draft(ctx.draft.id).status == "complete"
    end
  end

  describe "disconnect grace" do
    test "shrinks the current picker's clock to 60s", ctx do
      # 90s clock + fixed clock -> deadline math is deterministic
      start(ctx.draft, ctx.duel, pick_clock_seconds: 90, now_fun: fn -> @fixed end)
      Server.ready(ctx.draft.id, ctx.challenger.id)
      Server.ready(ctx.draft.id, ctx.opponent.id)

      Server.disconnected(ctx.draft.id, ctx.challenger.id)
      state = Server.get_state(ctx.draft.id)

      assert state.clock_deadline == DateTime.to_iso8601(DateTime.add(@fixed, 60, :second))
    end
  end

  describe "crash recovery" do
    test "replays persisted picks to rebuild live state", ctx do
      pid = start(ctx.draft, ctx.duel)
      Server.ready(ctx.draft.id, ctx.challenger.id)
      Server.ready(ctx.draft.id, ctx.opponent.id)
      pg = player_at("PG", 0)
      Server.make_pick(ctx.draft.id, ctx.challenger.id, pg.id)

      # simulate a crash: stop the server (it unregisters from the Registry)
      GenServer.stop(pid)

      # restart fresh from persisted state
      reloaded_duel = Repo.get(Duel, ctx.duel.id)
      start(ctx.draft, reloaded_duel)

      state = Server.get_state(ctx.draft.id)
      assert state.phase == :active
      assert state.pick_number == 2
      assert state.first_picker_id == ctx.challenger.id
      assert state.current_picker_id == ctx.opponent.id
      assert state.rosters[ctx.challenger.id] == %{"G1" => pg.id}
    end
  end

  describe "cancel (no-show)" do
    test "a participant cancels the lobby — draft + duel go to cancelled, no forfeit", ctx do
      start(ctx.draft, ctx.duel)
      Server.ready(ctx.draft.id, ctx.challenger.id)

      state = Server.cancel(ctx.draft.id, ctx.challenger.id)
      assert state.phase == :cancelled
      assert Drafts.get_draft(ctx.draft.id).status == "cancelled"
      assert Repo.get(Duel, ctx.duel.id).status == "cancelled"
    end
  end

  describe "completion-boundary crash recovery" do
    test "replay heals a draft whose final pick persisted but completion didn't", ctx do
      # all picks persisted, but draft left "active" / duel "drafting" (the crash window)
      {:ok, _} = Drafts.start_active(ctx.draft, ctx.challenger.id)
      order = Drafts.build_pick_order(ctx.challenger.id, ctx.opponent.id, 5)
      players = Repo.all(from p in Player, where: p.sport == "wnba", limit: 10)

      Enum.with_index(players, 1)
      |> Enum.each(fn {player, n} ->
        {:ok, _} =
          Drafts.record_pick(%{
            draft_id: ctx.draft.id,
            pick_number: n,
            user_id: Drafts.picker_for(order, n),
            player_id: player.id,
            slot: "PG1",
            auto_picked: true
          })
      end)

      assert Drafts.get_draft(ctx.draft.id).status == "active"

      # a fresh server replays and must heal the durable state
      reloaded = Repo.get(Duel, ctx.duel.id)
      start(ctx.draft, reloaded)

      assert Server.get_state(ctx.draft.id).phase == :complete
      assert Drafts.get_draft(ctx.draft.id).status == "complete"
      assert Repo.get(Duel, ctx.duel.id).status == "drafted"
    end
  end

  # --- helpers ------------------------------------------------------------

  defp expire(pid, draft_id) do
    st = Server.get_state(draft_id)
    send(pid, {:clock_expired, st.pick_number})
    Server.get_state(draft_id)
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{
        "username" => name,
        "email" => "#{name}@example.com",
        "password" => "password123"
      })

    u
  end

  defp accepted_duel(challenger, opponent) do
    future = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

    Repo.insert!(%Duel{
      challenger_id: challenger.id,
      opponent_id: opponent.id,
      sport: "wnba",
      draft_type: "snake",
      lineup_template: "wnba_standard",
      roster_size: 5,
      pick_clock_seconds: 60,
      scoring_rules: %{},
      draft_starts_at: future,
      status: "accepted"
    })
  end

  # 3 players per position, projections descending so PG > SG > SF > PF > C.
  defp pool do
    positions = ~w(PG SG SF PF C)

    for {pos, pi} <- Enum.with_index(positions), n <- 1..3 do
      Repo.insert!(%Player{
        sport: "wnba",
        external_id: "test-#{pos}-#{n}",
        name: "#{pos} Player #{n}",
        team: "TST",
        position: pos,
        projection: 100.0 - pi * 10 - n
      })
    end
  end

  defp player_at(position, idx) do
    Repo.all(from p in Player, where: p.position == ^position and p.sport == "wnba", order_by: [desc: p.projection])
    |> Enum.at(idx)
  end
end
