defmodule HeadsUp.StatsTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.{Accounts, Repo, Stats}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Settlement.Result
  alias HeadsUp.Social.Friendship

  setup do
    %{a: user("a"), b: user("b"), c: user("c")}
  end

  test "record_for: wins/losses/points/streak/recent from settled duels", %{a: a, b: b, c: c} do
    # oldest → newest
    settled(a, b, a, 100.0, 80.0, ts(1))
    settled(c, a, c, 90.0, 70.0, ts(2))
    settled(a, b, a, 110.0, 60.0, ts(3))

    r = Stats.record_for(a.id)
    assert r.wins == 2 and r.losses == 1 and r.ties == 0 and r.played == 3
    assert r.win_pct == 0.667
    assert r.points_for == 280.0 and r.points_against == 230.0
    # newest first: win, loss, win → current streak is a single win
    assert r.recent == ["W", "L", "W"]
    assert r.streak == %{type: "win", count: 1}
  end

  test "ties count and break a streak", %{a: a, b: b} do
    settled(a, b, a, 50.0, 40.0, ts(1))
    settled(a, b, nil, 50.0, 50.0, ts(2))

    r = Stats.record_for(a.id)
    assert r.ties == 1 and r.wins == 1
    assert r.streak == %{type: "tie", count: 1}
    assert r.recent == ["T", "W"]
  end

  test "head_to_head groups by opponent", %{a: a, b: b, c: c} do
    settled(a, b, a, 100.0, 80.0, ts(1))
    settled(a, b, a, 100.0, 90.0, ts(2))
    settled(c, a, c, 70.0, 40.0, ts(3))

    h2h = Stats.head_to_head(a.id)
    by_opp = Map.new(h2h, &{&1.opponent.id, &1})

    assert by_opp[b.id].wins == 2 and by_opp[b.id].played == 2
    assert by_opp[c.id].losses == 1 and by_opp[c.id].played == 1
    # most-played opponent first
    assert hd(h2h).opponent.id == b.id
  end

  test "leaderboard ranks the viewer + friends by wins", %{a: a, b: b, c: c} do
    friend(a, b)
    friend(a, c)
    settled(a, b, a, 100.0, 80.0, ts(1))
    settled(a, b, a, 100.0, 80.0, ts(2))
    settled(c, a, c, 90.0, 70.0, ts(3))

    board = Stats.leaderboard(a)
    assert Enum.map(board, &{&1.user.id, &1.rank, &1.wins}) == [{a.id, 1, 2}, {c.id, 2, 1}, {b.id, 3, 0}]
  end

  # --- helpers ------------------------------------------------------------

  defp ts(n), do: DateTime.utc_now() |> DateTime.add(n, :second) |> DateTime.truncate(:second)

  defp settled(c, o, winner, cp, op, settled_at) do
    duel =
      Repo.insert!(%Duel{
        challenger_id: c.id,
        opponent_id: o.id,
        sport: "wnba",
        draft_type: "snake",
        lineup_template: "wnba_standard",
        roster_size: 5,
        pick_clock_seconds: 60,
        scoring_rules: %{},
        draft_starts_at: settled_at,
        status: "settled",
        winner_id: winner && winner.id,
        settled_at: settled_at
      })

    Repo.insert!(%Result{
      duel_id: duel.id,
      winner_id: winner && winner.id,
      is_tie: is_nil(winner),
      challenger_points: cp,
      opponent_points: op,
      settled_at: settled_at
    })

    duel
  end

  defp friend(a, b), do: Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})

  defp user(name) do
    {:ok, u} = Accounts.register_user(%{"username" => "usr#{name}", "email" => "#{name}@example.com", "password" => "password123"})
    u
  end
end
