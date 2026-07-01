defmodule HeadsUp.HomeTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.{Accounts, Home, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Settlement.Result

  setup do
    %{a: user("a"), b: user("b")}
  end

  test "summary buckets duels by the action they need", %{a: a, b: b} do
    # a is challenged by b → needs response
    duel(b, a, "pending")
    # a challenged b → waiting on them
    duel(a, b, "pending")
    # ready/in-progress drafts
    duel(a, b, "accepted")
    duel(b, a, "drafting")
    # drafted, awaiting settlement
    duel(a, b, "drafted")
    # settled (a win) → recent results + record
    settled(a, b, a)

    s = Home.summary(a)

    assert length(s.needs_response) == 1
    assert hd(s.needs_response).opponent_id == a.id
    assert length(s.waiting_on_them) == 1
    assert length(s.draft_ready) == 2
    assert length(s.awaiting) == 1
    assert length(s.recent_results) == 1
    assert s.record.wins == 1 and s.record.played == 1
  end

  test "recent_results keeps only the 3 newest settled", %{a: a, b: b} do
    for _ <- 1..5, do: settled(a, b, a)
    s = Home.summary(a)
    assert length(s.recent_results) == 3
  end

  # --- helpers ------------------------------------------------------------

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp duel(c, o, status) do
    Repo.insert!(%Duel{
      challenger_id: c.id,
      opponent_id: o.id,
      sport: "wnba",
      draft_type: "snake",
      lineup_template: "wnba_standard",
      roster_size: 5,
      pick_clock_seconds: 60,
      scoring_rules: %{},
      draft_starts_at: now(),
      status: status
    })
  end

  defp settled(c, o, winner) do
    d =
      Repo.insert!(%Duel{
        challenger_id: c.id,
        opponent_id: o.id,
        sport: "wnba",
        draft_type: "snake",
        lineup_template: "wnba_standard",
        roster_size: 5,
        pick_clock_seconds: 60,
        scoring_rules: %{},
        draft_starts_at: now(),
        status: "settled",
        winner_id: winner.id,
        settled_at: now()
      })

    Repo.insert!(%Result{
      duel_id: d.id,
      winner_id: winner.id,
      is_tie: false,
      challenger_points: 100.0,
      opponent_points: 80.0,
      settled_at: now()
    })

    d
  end

  defp user(name) do
    {:ok, u} = Accounts.register_user(%{"username" => "usr#{name}", "email" => "#{name}@example.com", "password" => "password123"})
    u
  end
end
