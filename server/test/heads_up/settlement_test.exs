defmodule HeadsUp.SettlementTest.StubStats do
  @moduledoc false
  @behaviour HeadsUp.Settlement.StatsProvider
  alias HeadsUp.Settlement.Window

  @impl true
  def stats_final?(%Window{}), do: true

  # Deterministic: a player named "Star ..." scores 50 points, everyone else 0.
  @impl true
  def fetch_stats(players, %Window{}) do
    Map.new(players, fn p ->
      pts = if String.starts_with?(p.name, "Star"), do: 50, else: 0
      {p.id, %{"point" => pts}}
    end)
  end
end

defmodule HeadsUp.SettlementTest do
  # async: false -> shared sandbox so the app-supervised worker can hit the DB.
  use HeadsUp.DataCase, async: false

  alias HeadsUp.{Accounts, Drafts, Repo, Settlement}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Drafts.Pick
  alias HeadsUp.Settlement.{Result, Worker}
  alias HeadsUp.Sports.Player

  setup do
    Application.put_env(:heads_up, :stats_provider, HeadsUp.SettlementTest.StubStats)
    on_exit(fn -> Application.put_env(:heads_up, :stats_provider, HeadsUp.Settlement.Stats.Mock) end)
    :ok
  end

  describe "settle_duel/1" do
    test "scores both rosters and declares the higher total the winner" do
      c = user("chal")
      o = user("oppo")
      duel = drafted_duel(c, o, %{"point" => 1}, past_window())
      with_rosters(duel, player("Star Wing"), player("Bench Guard"))

      assert {:ok, result, settled} = Settlement.settle_duel(duel.id)
      assert settled.status == "settled"
      assert settled.winner_id == c.id
      assert result.winner_id == c.id
      refute result.is_tie
      assert result.challenger_points == 50.0
      assert result.opponent_points == 0.0
      assert %{"challenger" => %{"players" => [cp]}, "opponent" => %{"players" => [_]}} = result.breakdown
      assert cp["name"] == "Star Wing"
      assert cp["points"] == 50.0
    end

    test "equal totals settle as a tie (winner_id nil)" do
      c = user("c2")
      o = user("o2")
      duel = drafted_duel(c, o, %{"point" => 1}, past_window())
      with_rosters(duel, player("Bench A"), player("Bench B"))

      assert {:ok, result, settled} = Settlement.settle_duel(duel.id)
      assert result.is_tie
      assert settled.winner_id == nil
      assert result.challenger_points == 0.0
      assert result.opponent_points == 0.0
    end

    test "settling twice is an idempotent no-op (exactly one result row)" do
      c = user("c3")
      o = user("o3")
      duel = drafted_duel(c, o, %{"point" => 1}, past_window())
      with_rosters(duel, player("Star Z"), player("Bench Z"))

      assert {:ok, _result, _settled} = Settlement.settle_duel(duel.id)
      assert {:ok, %Duel{status: "settled"}} = Settlement.settle_duel(duel.id)
      assert Repo.aggregate(from(r in Result, where: r.duel_id == ^duel.id), :count) == 1
    end

    test "a non-drafted duel can't be settled" do
      c = user("c4")
      o = user("o4")
      duel = pending_duel(c, o)
      assert {:error, :not_drafted} = Settlement.settle_duel(duel.id)
    end

    test "a one-sided draft (a user with no picks) is not silently settled as a win" do
      c = user("c4b")
      o = user("o4b")
      duel = drafted_duel(c, o, %{"point" => 1}, past_window())
      {:ok, draft} = Drafts.get_or_create_draft_for_duel(duel)

      # only the challenger drafted anyone
      Repo.insert!(%Pick{
        draft_id: draft.id,
        user_id: c.id,
        player_id: player("Star Solo").id,
        pick_number: 1,
        slot: "PG1",
        auto_picked: false
      })

      assert {:error, :incomplete_draft} = Settlement.settle_duel(duel.id)
      assert Repo.get(Duel, duel.id).status == "drafted"
    end
  end

  describe "due_duels/1" do
    test "selects drafted duels whose window has closed, not future ones" do
      c = user("c5")
      o = user("o5")
      due = drafted_duel(c, o, %{"point" => 1}, past_window())
      not_due = drafted_duel(c, o, %{"point" => 1}, future_window())

      ids = Settlement.due_duels() |> Enum.map(& &1.id)
      assert due.id in ids
      refute not_due.id in ids
    end
  end

  describe "automatic worker" do
    test "a forced sweep settles every due duel" do
      c = user("c6")
      o = user("o6")
      duel = drafted_duel(c, o, %{"point" => 1}, past_window())
      with_rosters(duel, player("Star Q"), player("Bench Q"))

      assert :ok = Worker.trigger_now()
      assert Repo.get(Duel, duel.id).status == "settled"
      assert Settlement.get_result(duel.id).winner_id == c.id
    end
  end

  # --- helpers ------------------------------------------------------------

  defp past_window, do: DateTime.utc_now() |> DateTime.add(-60) |> DateTime.truncate(:second)
  defp future_window, do: DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

  defp drafted_duel(c, o, rules, window_end) do
    past = DateTime.utc_now() |> DateTime.add(-7200) |> DateTime.truncate(:second)

    Repo.insert!(%Duel{
      challenger_id: c.id,
      opponent_id: o.id,
      sport: "wnba",
      draft_type: "snake",
      lineup_template: "wnba_standard",
      roster_size: 5,
      pick_clock_seconds: 60,
      scoring_rules: rules,
      draft_starts_at: past,
      status: "drafted",
      scoring_window_start: DateTime.add(window_end, -3600),
      scoring_window_end: window_end
    })
  end

  defp pending_duel(c, o) do
    Repo.insert!(%Duel{
      challenger_id: c.id,
      opponent_id: o.id,
      sport: "wnba",
      draft_type: "snake",
      lineup_template: "wnba_standard",
      roster_size: 5,
      pick_clock_seconds: 60,
      scoring_rules: %{},
      draft_starts_at: DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second),
      status: "pending"
    })
  end

  defp with_rosters(duel, challenger_player, opponent_player) do
    {:ok, draft} = Drafts.get_or_create_draft_for_duel(duel)

    Repo.insert!(%Pick{
      draft_id: draft.id,
      user_id: duel.challenger_id,
      player_id: challenger_player.id,
      pick_number: 1,
      slot: "PG1",
      auto_picked: false
    })

    Repo.insert!(%Pick{
      draft_id: draft.id,
      user_id: duel.opponent_id,
      player_id: opponent_player.id,
      pick_number: 2,
      slot: "PG1",
      auto_picked: false
    })

    draft
  end

  defp player(name) do
    Repo.insert!(%Player{
      sport: "wnba",
      external_id: "test-" <> String.replace(name, " ", "-"),
      name: name,
      team: "TST",
      position: "PG",
      projection: 50.0
    })
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{
        "username" => "usr#{name}",
        "email" => "#{name}@example.com",
        "password" => "password123"
      })

    u
  end
end
