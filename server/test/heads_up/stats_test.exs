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

  test "history_vs lists only the duels between those two, newest first", %{a: a, b: b, c: c} do
    settled(a, b, a, 100.0, 80.0, ts(1))
    settled(a, b, b, 60.0, 90.0, ts(2))
    settled(a, c, a, 70.0, 40.0, ts(3))

    assert [newest, oldest] = Stats.history_vs(a.id, b.id)
    assert %{outcome: :loss, pf: 60.0, pa: 90.0} = newest
    assert %{outcome: :win, pf: 100.0, pa: 80.0} = oldest
    assert DateTime.compare(newest.settled_at, oldest.settled_at) == :gt
  end

  test "history_vs respects the limit", %{a: a, b: b} do
    for i <- 1..4, do: settled(a, b, a, 100.0, 80.0, ts(i))

    assert length(Stats.history_vs(a.id, b.id, 2)) == 2
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

  describe "group duels in stats" do
    test "count in the record with win = 1st place (below-top is a LOSS, not a tie)", %{a: a, b: b, c: c} do
      settled_group([{b, 90.0}, {c, 70.0}, {a, 50.0}], b, ts(1))

      assert %{wins: 1, losses: 0, points_for: 90.0, points_against: 70.0} = Stats.record_for(b.id)
      assert %{wins: 0, losses: 1, points_for: 50.0, points_against: 90.0} = Stats.record_for(a.id)
    end

    test "a shared top is a tie for rank 1 and a loss for everyone below", %{a: a, b: b, c: c} do
      settled_group([{a, 80.0}, {b, 80.0}, {c, 40.0}], nil, ts(1))

      assert %{ties: 1, losses: 0} = Stats.record_for(a.id)
      assert %{ties: 1, losses: 0} = Stats.record_for(b.id)
      assert %{ties: 0, losses: 1} = Stats.record_for(c.id)
    end

    test "head_to_head stays 1v1-only", %{a: a, b: b, c: c} do
      settled_group([{a, 90.0}, {b, 70.0}, {c, 50.0}], a, ts(1))
      settled(a, b, a, 100.0, 80.0, ts(2))

      h2h = Stats.head_to_head(a.id)
      assert [only] = h2h
      assert only.opponent.id == b.id and only.played == 1
    end

    test "leaderboard counts a shared group duel once per person", %{a: a, b: b, c: c} do
      friend(a, b)
      friend(a, c)
      settled_group([{a, 90.0}, {b, 70.0}, {c, 50.0}], a, ts(1))

      board = Stats.leaderboard(a)
      assert Enum.map(board, &{&1.user.id, &1.wins, &1.played}) == [{a.id, 1, 1}, {b.id, 0, 1}, {c.id, 0, 1}]
    end
  end

  # --- helpers ------------------------------------------------------------

  defp ts(n), do: DateTime.utc_now() |> DateTime.add(n, :second) |> DateTime.truncate(:second)

  # A settled group duel. `finishers` = [{user, total}] best-first; ranks are
  # competition-style (equal totals share). Seats: first finisher is the host.
  defp settled_group(finishers, winner, settled_at) do
    duel =
      Repo.insert!(%Duel{
        challenger_id: elem(hd(finishers), 0).id,
        opponent_id: nil,
        sport: "wnba",
        draft_type: "snake",
        lineup_template: "wnba_standard",
        roster_size: 6,
        pick_clock_seconds: 60,
        scoring_rules: %{},
        draft_starts_at: settled_at,
        status: "settled",
        winner_id: winner && winner.id,
        settled_at: settled_at
      })

    for {{u, _total}, seat} <- Enum.with_index(finishers) do
      Repo.insert!(%HeadsUp.Contests.Participant{duel_id: duel.id, user_id: u.id, seat: seat, status: "accepted"})
    end

    standings =
      finishers
      |> Enum.with_index()
      |> Enum.map_reduce(nil, fn {{u, total}, idx}, prev ->
        rank = if prev && elem(prev, 0) == total, do: elem(prev, 1), else: idx + 1
        {%{"user_id" => u.id, "total" => total, "rank" => rank, "players" => []}, {total, rank}}
      end)
      |> elem(0)

    [first, second | _] = finishers

    Repo.insert!(%Result{
      duel_id: duel.id,
      winner_id: winner && winner.id,
      is_tie: is_nil(winner),
      challenger_points: elem(first, 1),
      opponent_points: elem(second, 1),
      settled_at: settled_at,
      breakdown: %{"standings" => standings}
    })

    duel
  end

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

  describe "rivalry/2" do
    test "tally, form, run, and the bragging-rights tiles", %{a: a, b: b, c: c} do
      settled(a, b, a, 100.0, 80.0, ts(1))
      settled(b, a, a, 90.0, 96.2, ts(2))
      settled(a, b, b, 60.0, 90.0, ts(3))
      # noise: a different rivalry must not leak in
      settled(a, c, a, 70.0, 40.0, ts(4))

      r = Stats.rivalry(a.id, b.id)
      assert %{wins: 2, losses: 1, ties: 0, played: 3} = r
      assert r.form == ["L", "W", "W"]
      assert r.run == "L1"
      # margins: +20, +6.2, −30 → avg −1.3; best win +20
      assert r.avg_margin == -1.3
      assert r.best_win == 20.0
      assert length(r.history) == 3
      assert hd(r.history).outcome == :loss
    end

    test "never-played rivals get the honest empty shape", %{a: a, b: b} do
      r = Stats.rivalry(a.id, b.id)
      assert %{wins: 0, losses: 0, played: 0, run: nil, avg_margin: nil, best_win: nil, history: []} = r
    end

    test "stories: tie, blowout, squeaker, and the margin fallback", %{a: a, b: b} do
      settled(a, b, nil, 88.0, 88.0, ts(1))
      settled(a, b, a, 100.0, 75.0, ts(2))
      settled(a, b, b, 90.0, 91.2, ts(3))
      settled(a, b, b, 80.0, 95.0, ts(4))
      settled(a, b, b, 80.0, 90.0, ts(5))

      stories = Stats.rivalry(a.id, b.id) |> Map.get(:history) |> Enum.map(& &1.story)

      # newest first: plain loss, their series-best, squeaker loss, blowout win, tie
      assert [
               "Dropped it by 10.0",
               "Their biggest win of the series",
               "Slipped away by 1.2",
               "Never in doubt — up 25.0",
               "Dead heat — split the pot."
             ] = stories
    end

    test "the series-best win gets named once there is more than one", %{a: a, b: b} do
      settled(a, b, a, 100.0, 90.0, ts(1))
      settled(a, b, a, 95.0, 80.0, ts(2))

      [newest, _oldest] = Stats.rivalry(a.id, b.id).history
      assert newest.story == "Your biggest win of the series"
    end

    test "the top performer carries the story when the breakdown has one", %{a: a, b: b} do
      duel = settled(a, b, a, 96.2, 89.7, ts(1))
      # a second, bigger win so the first isn't "biggest of the series"
      settled(a, b, a, 110.0, 90.0, ts(2))

      Repo.get_by!(Result, duel_id: duel.id)
      |> Ecto.Changeset.change(
        breakdown: %{
          "challenger" => %{
            "user_id" => a.id,
            "total" => 96.2,
            "players" => [
              %{"name" => "Napheesa Collier", "points" => 31.2},
              %{"name" => "Sabrina Ionescu", "points" => 20.0}
            ]
          },
          "opponent" => %{"user_id" => b.id, "total" => 89.7, "players" => []}
        }
      )
      |> Repo.update!()

      [_newest, older] = Stats.rivalry(a.id, b.id).history
      assert older.story == "Collier 31.2 carried it"
    end

    test "their star gets the nuclear line on a loss", %{a: a, b: b} do
      duel = settled(b, a, b, 108.9, 101.4, ts(1))
      settled(b, a, b, 120.0, 90.0, ts(2))

      Repo.get_by!(Result, duel_id: duel.id)
      |> Ecto.Changeset.change(
        breakdown: %{
          "challenger" => %{
            "user_id" => b.id,
            "total" => 108.9,
            "players" => [%{"name" => "Caitlin Clark", "points" => 38.6}]
          },
          "opponent" => %{"user_id" => a.id, "total" => 101.4, "players" => []}
        }
      )
      |> Repo.update!()

      [_newest, older] = Stats.rivalry(a.id, b.id).history
      assert older.story == "Clark went nuclear (38.6)"
    end
  end

  defp friend(a, b), do: Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})

  defp user(name) do
    {:ok, u} = Accounts.register_user(%{"username" => "usr#{name}", "email" => "#{name}@example.com", "password" => "password123"})
    u
  end
end
