defmodule HeadsUp.AchievementsTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.{Accounts, Achievements, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Settlement.Result

  setup do
    %{a: user("a"), b: user("b")}
  end

  test "earns trophies from settled duels; locks the ones not reached", %{a: a, b: b} do
    # 3 straight wins; the first is a 105-pt blowout with a 55-pt player.
    settled(a, b, a, 105.0, 70.0, top: 55.0, at: 1)
    settled(a, b, a, 60.0, 50.0, at: 2)
    settled(a, b, a, 60.0, 55.0, at: 3)

    by_key = Achievements.for_user(a.id) |> Map.new(&{&1.key, &1})

    assert by_key["first_win"].earned
    assert by_key["hat_trick"].earned and by_key["hat_trick"].value == 3
    assert by_key["century"].earned and by_key["century"].value == 105
    assert by_key["sharpshooter"].earned and by_key["sharpshooter"].value == 55
    assert by_key["blowout"].earned and by_key["blowout"].value == 35

    refute by_key["on_fire"].earned
    refute by_key["veteran"].earned
    refute by_key["rivalry"].earned
  end

  test "a player with no duels has everything locked at zero", %{a: a} do
    for tr <- Achievements.for_user(a.id) do
      assert tr.value == 0 and tr.earned == false
    end
  end

  test "a group win earns Party Crasher and counts as a win; rivalry ignores groups", %{a: a, b: b} do
    c = user("c")
    settled_group([{a, 92.5}, {b, 70.0}, {c, 55.0}], a, at: 1, top: 41.0)

    a_keys = Achievements.for_user(a.id) |> Map.new(&{&1.key, &1})
    assert a_keys["party_crasher"].earned
    assert a_keys["first_win"].earned
    assert a_keys["blowout"].value == 23
    assert a_keys["sharpshooter"].value == 41
    assert a_keys["rivalry"].value == 0

    b_keys = Achievements.for_user(b.id) |> Map.new(&{&1.key, &1})
    refute b_keys["party_crasher"].earned
    assert b_keys["veteran"].value == 1
  end

  # --- helpers ------------------------------------------------------------

  # A settled 3-player group. `finishers` = [{user, total}] best-first; the
  # winner's top drafted player scores `opts[:top]`.
  defp settled_group(finishers, winner, opts) do
    at = DateTime.utc_now() |> DateTime.add(Keyword.fetch!(opts, :at), :second) |> DateTime.truncate(:second)
    top = Keyword.get(opts, :top, 0.0)

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
        draft_starts_at: at,
        status: "settled",
        winner_id: winner && winner.id,
        settled_at: at
      })

    for {{u, _}, seat} <- Enum.with_index(finishers) do
      Repo.insert!(%HeadsUp.Contests.Participant{duel_id: duel.id, user_id: u.id, seat: seat, status: "accepted"})
    end

    standings =
      finishers
      |> Enum.with_index(1)
      |> Enum.map(fn {{u, total}, rank} ->
        players = if winner && u.id == winner.id, do: [%{"points" => top}, %{"points" => 8.0}], else: [%{"points" => 12.0}]
        %{"user_id" => u.id, "total" => total, "rank" => rank, "players" => players}
      end)

    [first, second | _] = finishers

    Repo.insert!(%Result{
      duel_id: duel.id,
      winner_id: winner && winner.id,
      is_tie: is_nil(winner),
      challenger_points: elem(first, 1),
      opponent_points: elem(second, 1),
      settled_at: at,
      breakdown: %{"standings" => standings}
    })

    duel
  end

  defp settled(c, o, winner, cp, op, opts) do
    at = DateTime.utc_now() |> DateTime.add(Keyword.fetch!(opts, :at), :second) |> DateTime.truncate(:second)
    top = Keyword.get(opts, :top, 0.0)

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
        draft_starts_at: at,
        status: "settled",
        winner_id: winner && winner.id,
        settled_at: at
      })

    Repo.insert!(%Result{
      duel_id: duel.id,
      winner_id: winner && winner.id,
      is_tie: is_nil(winner),
      challenger_points: cp,
      opponent_points: op,
      settled_at: at,
      breakdown: %{
        "challenger" => %{"user_id" => c.id, "total" => cp, "players" => [%{"points" => top}, %{"points" => 10.0}]},
        "opponent" => %{"user_id" => o.id, "total" => op, "players" => [%{"points" => 20.0}]}
      }
    })

    duel
  end

  defp user(name) do
    {:ok, u} = Accounts.register_user(%{"username" => "usr#{name}", "email" => "#{name}@example.com", "password" => "password123"})
    u
  end
end
