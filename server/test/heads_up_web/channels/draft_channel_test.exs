defmodule HeadsUpWeb.DraftChannelTest do
  use HeadsUpWeb.ChannelCase, async: false

  alias HeadsUp.{Accounts, Drafts, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUpWeb.UserSocket

  setup do
    challenger = user("chal")
    opponent = user("oppo")
    stranger = user("strange")
    duel = accepted_duel(challenger, opponent)
    {:ok, _draft} = Drafts.get_or_create_draft_for_duel(duel)

    %{challenger: challenger, opponent: opponent, stranger: stranger, duel: duel}
  end

  describe "socket auth" do
    test "rejects a connection without a valid token" do
      assert :error = connect(UserSocket, %{"token" => "garbage"})
      assert :error = connect(UserSocket, %{})
    end

    test "accepts a valid token", ctx do
      assert {:ok, socket} = connect(UserSocket, %{"token" => token(ctx.challenger)})
      assert socket.assigns.current_user_id == ctx.challenger.id
    end
  end

  describe "join authorization" do
    test "a participant joins and gets a lobby snapshot", ctx do
      {:ok, _sock, reply} = join_as(ctx.challenger, ctx.duel)
      assert reply.state.phase == :lobby
      assert reply.state.duel_id == ctx.duel.id
    end

    test "a non-participant is rejected", ctx do
      {:ok, socket} = connect(UserSocket, %{"token" => token(ctx.stranger)})

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, "draft:#{ctx.duel.id}", %{})
    end
  end

  describe "draft flow over the channel" do
    test "both ready -> coin flip broadcasts an active-phase update to both", ctx do
      {:ok, chal_sock, _} = join_as(ctx.challenger, ctx.duel)
      {:ok, oppo_sock, _} = join_as(ctx.opponent, ctx.duel)

      ref = push(chal_sock, "ready", %{})
      assert_reply ref, :ok

      ref2 = push(oppo_sock, "ready", %{})
      assert_reply ref2, :ok

      # the engine broadcasts a full snapshot; phase should reach :active
      assert_push "update", %{state: %{phase: :active}}, 1000
    end

    test "an out-of-turn pick is rejected to the offender", ctx do
      {:ok, chal_sock, _} = join_as(ctx.challenger, ctx.duel)
      {:ok, oppo_sock, _} = join_as(ctx.opponent, ctx.duel)
      push(chal_sock, "ready", %{}) |> assert_reply(:ok)
      push(oppo_sock, "ready", %{}) |> assert_reply(:ok)

      # challenger won the (default) coin flip in this fixture? Not guaranteed —
      # so just assert the wrong player gets an error. Find who is NOT on the clock.
      assert_push "update", %{state: %{phase: :active, current_picker_id: on_clock}}, 1000
      off_clock_sock = if on_clock == ctx.challenger.id, do: oppo_sock, else: chal_sock

      ref = push(off_clock_sock, "make_pick", %{"player_id" => first_player_id()})
      assert_reply ref, :error, %{reason: "not_your_turn"}
    end
  end

  describe "reactions" do
    test "a reaction is relayed to everyone in the room, sender included", ctx do
      {:ok, chal_sock, _} = join_as(ctx.challenger, ctx.duel)
      {:ok, _oppo_sock, _} = join_as(ctx.opponent, ctx.duel)

      push(chal_sock, "react", %{"emoji" => "🔥"})

      chal_id = ctx.challenger.id
      assert_broadcast "reaction", %{emoji: "🔥", user_id: ^chal_id}
    end

    test "an off-menu emoji is dropped, not relayed", ctx do
      {:ok, chal_sock, _} = join_as(ctx.challenger, ctx.duel)

      push(chal_sock, "react", %{"emoji" => "🖕"})
      push(chal_sock, "react", %{"emoji" => String.duplicate("🔥", 50)})

      refute_broadcast "reaction", %{}
    end
  end

  # --- helpers ---

  # Returns {:ok, joined_socket, join_reply}.
  defp join_as(user, duel) do
    {:ok, socket} = connect(UserSocket, %{"token" => token(user)})
    {:ok, reply, joined} = subscribe_and_join(socket, "draft:#{duel.id}", %{})
    {:ok, joined, reply}
  end

  defp token(user), do: Accounts.create_user_api_token(user)

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

    duel =
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

    pool()
    duel
  end

  defp pool do
    for {pos, pi} <- Enum.with_index(~w(PG SG SF PF C)), n <- 1..3 do
      Repo.insert!(%HeadsUp.Sports.Player{
        sport: "wnba",
        external_id: "test-#{pos}-#{n}",
        name: "#{pos} #{n}",
        team: "TST",
        position: pos,
        projection: 100.0 - pi * 10 - n
      })
    end
  end

  defp first_player_id do
    import Ecto.Query
    Repo.one(from p in HeadsUp.Sports.Player, where: p.sport == "wnba", limit: 1, select: p.id)
  end
end
