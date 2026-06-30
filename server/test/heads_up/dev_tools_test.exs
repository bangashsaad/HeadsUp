defmodule HeadsUp.DevToolsTest do
  use HeadsUp.DataCase, async: false

  alias HeadsUp.{Accounts, DevTools, Drafts, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Drafts.Pick
  alias HeadsUp.Sports.Player

  setup do
    prev = Application.get_env(:heads_up, :dev_routes)
    Application.put_env(:heads_up, :dev_routes, true)
    on_exit(fn -> Application.put_env(:heads_up, :dev_routes, prev) end)
    :ok
  end

  test "settles a drafted duel and repoints the window to the ET day (in UTC)" do
    {duel, _c, _o} = drafted_with_rosters()

    assert {:ok, result, settled} = DevTools.settle_on_date(duel.id, ~D[2026-06-28])
    assert settled.status == "settled"
    assert result.duel_id == duel.id

    reloaded = Repo.get(Duel, duel.id)
    assert reloaded.scoring_window_start == ~U[2026-06-28 04:00:00Z]
    assert reloaded.scoring_window_end == ~U[2026-06-29 03:59:59Z]
  end

  test "accepts a YYYY-MM-DD string" do
    {duel, _c, _o} = drafted_with_rosters()
    assert {:ok, _result, settled} = DevTools.settle_on_date(duel.id, "2026-06-28")
    assert settled.status == "settled"
  end

  test "is idempotent: a second call is a no-op" do
    {duel, _c, _o} = drafted_with_rosters()
    assert {:ok, _result, _settled} = DevTools.settle_on_date(duel.id, ~D[2026-06-28])
    assert {:ok, :already_settled} = DevTools.settle_on_date(duel.id, ~D[2026-06-28])
  end

  test "refuses a non-drafted duel" do
    {c, o} = {user("c"), user("o")}
    duel = duel(c, o, "pending")
    assert {:error, {:not_drafted, "pending"}} = DevTools.settle_on_date(duel.id, ~D[2026-06-28])
  end

  test "is blocked outside dev (dev_routes off)" do
    Application.put_env(:heads_up, :dev_routes, false)
    {duel, _c, _o} = drafted_with_rosters()
    assert {:error, :dev_only} = DevTools.settle_on_date(duel.id, ~D[2026-06-28])
  end

  # --- fixtures -----------------------------------------------------------

  defp drafted_with_rosters do
    c = user("chal")
    o = user("oppo")
    duel = duel(c, o, "drafted")
    {:ok, draft} = Drafts.get_or_create_draft_for_duel(duel)

    Repo.insert!(%Pick{draft_id: draft.id, user_id: c.id, player_id: player("Alpha").id, pick_number: 1, slot: "G1", auto_picked: false})
    Repo.insert!(%Pick{draft_id: draft.id, user_id: o.id, player_id: player("Bravo").id, pick_number: 2, slot: "G1", auto_picked: false})

    {duel, c, o}
  end

  defp duel(c, o, status) do
    now = DateTime.utc_now() |> DateTime.add(-7200) |> DateTime.truncate(:second)

    Repo.insert!(%Duel{
      challenger_id: c.id,
      opponent_id: o.id,
      sport: "wnba",
      draft_type: "snake",
      lineup_template: "wnba_standard",
      roster_size: 5,
      pick_clock_seconds: 60,
      scoring_rules: %{"point" => 1},
      draft_starts_at: now,
      status: status,
      scoring_window_start: now,
      scoring_window_end: now
    })
  end

  defp player(name) do
    Repo.insert!(%Player{
      sport: "wnba",
      external_id: "dt-" <> name,
      name: name,
      team: "TST",
      position: "G",
      projection: 50.0
    })
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => "usr#{name}", "email" => "#{name}@example.com", "password" => "password123"})

    u
  end
end
