defmodule HeadsUp.SettlementLiveTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.{Accounts, Drafts, Repo, Settlement}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Drafts.Pick
  alias HeadsUp.Sports.Player

  @rules %{"point" => 1, "rebound" => 1.25, "assist" => 1.5}

  test "live_result scores both rosters and names a leader for a drafted duel" do
    c = user("c")
    o = user("o")
    duel = drafted_duel(c, o)
    cp = player("Challenger Star")
    op = player("Opponent Star")
    with_rosters(duel, cp, op)

    assert {:ok, live} = Settlement.live_result(duel.id)

    assert live.challenger.user_id == c.id
    assert live.opponent.user_id == o.id
    assert is_float(live.challenger.total)
    assert live.leader_id in [c.id, o.id, nil]
    # game-state counts come from the provider (Mock → one final game)
    assert %{final: _, live: _, upcoming: _} = live.games
    # the player breakdown is present for the scoreboard
    assert [%{player_id: _, points: _, stat_line: _} | _] = live.challenger.players
  end

  test "live_result refuses a non-drafted duel" do
    c = user("c")
    o = user("o")
    duel = drafted_duel(c, o)
    {:ok, _} = duel |> Ecto.Changeset.change(status: "pending") |> Repo.update()

    assert {:error, :not_live} = Settlement.live_result(duel.id)
  end

  # --- helpers ------------------------------------------------------------

  defp drafted_duel(c, o) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%Duel{
      challenger_id: c.id,
      opponent_id: o.id,
      sport: "wnba",
      draft_type: "snake",
      lineup_template: "wnba_standard",
      roster_size: 5,
      pick_clock_seconds: 60,
      scoring_rules: @rules,
      draft_starts_at: now,
      status: "drafted",
      scoring_window_start: DateTime.add(now, -3600),
      scoring_window_end: DateTime.add(now, 3600)
    })
  end

  defp with_rosters(duel, cp, op) do
    {:ok, draft} = Drafts.get_or_create_draft_for_duel(duel)

    Repo.insert!(%Pick{draft_id: draft.id, user_id: duel.challenger_id, player_id: cp.id, pick_number: 1, slot: "G1", auto_picked: false})
    Repo.insert!(%Pick{draft_id: draft.id, user_id: duel.opponent_id, player_id: op.id, pick_number: 2, slot: "G1", auto_picked: false})
  end

  defp player(name) do
    Repo.insert!(%Player{sport: "wnba", external_id: "test-" <> String.replace(name, " ", "-"), name: name, team: "TST", position: "G", projection: 50.0})
  end

  defp user(name) do
    {:ok, u} = Accounts.register_user(%{"username" => "usr#{name}#{System.unique_integer([:positive])}", "email" => "#{name}#{System.unique_integer([:positive])}@example.com", "password" => "password123"})
    u
  end
end
