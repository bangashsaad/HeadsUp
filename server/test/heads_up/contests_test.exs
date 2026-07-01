defmodule HeadsUp.ContestsTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.{Accounts, Contests, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Social.Friendship

  setup do
    a = user("a")
    b = user("b")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
    %{a: a, b: b}
  end

  describe "rematch/3" do
    test "clones terms into a fresh pending challenge to the same opponent", %{a: a, b: b} do
      duel = settled(a, b)

      assert {:ok, rematch} = Contests.rematch(a, duel.id)
      assert rematch.status == "pending"
      assert rematch.challenger_id == a.id and rematch.opponent_id == b.id
      assert rematch.sport == duel.sport
      assert rematch.lineup_template == duel.lineup_template
      assert rematch.pick_clock_seconds == duel.pick_clock_seconds
      assert rematch.scoring_rules == duel.scoring_rules
      assert rematch.parent_duel_id == duel.id
      assert rematch.draft_starts_at != nil
    end

    test "the opponent can rematch too — challenger flips to them", %{a: a, b: b} do
      duel = settled(a, b)
      assert {:ok, rematch} = Contests.rematch(b, duel.id)
      assert rematch.challenger_id == b.id and rematch.opponent_id == a.id
    end

    test "a stranger's duel is not found", %{a: a, b: b} do
      c = user("c")
      duel = settled(a, b)
      assert {:error, :not_found} = Contests.rematch(c, duel.id)
    end
  end

  # --- helpers ------------------------------------------------------------

  defp settled(c, o) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%Duel{
      challenger_id: c.id,
      opponent_id: o.id,
      sport: "wnba",
      draft_type: "snake",
      lineup_template: "wnba_standard",
      roster_size: 5,
      pick_clock_seconds: 90,
      scoring_rules: %{"point" => 1, "rebound" => 1.25},
      wager_cents: 0,
      draft_starts_at: now,
      status: "settled",
      winner_id: c.id,
      settled_at: now
    })
  end

  defp user(name) do
    {:ok, u} = Accounts.register_user(%{"username" => "usr#{name}", "email" => "#{name}@example.com", "password" => "password123"})
    u
  end
end
