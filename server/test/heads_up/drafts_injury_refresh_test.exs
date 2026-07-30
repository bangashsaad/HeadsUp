defmodule HeadsUp.DraftsInjuryRefreshTest do
  @moduledoc """
  The draft board snapshots its pool when the room opens, which can be hours
  before anyone picks. These cover the refresh that runs when picks actually
  start — and, more importantly, that it can NEVER delay the coin flip.
  """
  use HeadsUp.DataCase, async: false

  alias HeadsUp.{Accounts, Drafts, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Drafts.Server
  alias HeadsUp.Sports.Player

  # An injuries client that hangs. If the refresh were synchronous, a draft
  # start would block on this for the full duration.
  defmodule HangingClient do
    def injuries(_sport) do
      Process.sleep(3_000)
      {:ok, %{"injuries" => []}}
    end
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  defp seed_players do
    for i <- 1..20 do
      Repo.insert!(%Player{
        sport: "wnba",
        external_id: "#{9_000_000 + i}",
        name: "Refresh Player #{i}",
        team: "RFR",
        position: Enum.at(~w(G G F F C), rem(i, 5)),
        projection: 30.0 - i
      })
    end
  end

  defp accepted_duel(a, b) do
    Repo.insert!(%Duel{
      challenger_id: a.id,
      opponent_id: b.id,
      sport: "wnba",
      draft_type: "snake",
      lineup_template: "wnba_5",
      roster_size: 5,
      pick_clock_seconds: 60,
      scoring_rules: %{},
      stake_coins: 0,
      draft_starts_at: DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second),
      status: "accepted"
    })
  end

  test "a hanging injury feed does NOT delay the coin flip" do
    Application.put_env(:heads_up, :injuries_client, HangingClient)
    on_exit(fn -> Application.delete_env(:heads_up, :injuries_client) end)

    a = user("refa")
    b = user("refb")
    seed_players()
    duel = accepted_duel(a, b)
    {:ok, draft} = Drafts.get_or_create_draft_for_duel(duel)
    {:ok, _pid} = Drafts.Supervisor.ensure_started(draft.id, duel)

    Server.ready(draft.id, a.id)

    # The second ready triggers start_draft. With a 3s-hanging feed, a
    # synchronous refresh would push this well past a second.
    {micros, _} = :timer.tc(fn -> Server.ready(draft.id, b.id) end)

    assert Server.get_state(draft.id).phase == :active
    assert micros < 1_000_000, "draft start took #{div(micros, 1000)}ms — the refresh is blocking it"
  end

  test "a fresh report merges onto the live pool without disturbing the draft" do
    a = user("mrga")
    b = user("mrgb")
    seed_players()
    duel = accepted_duel(a, b)
    {:ok, draft} = Drafts.get_or_create_draft_for_duel(duel)
    {:ok, pid} = Drafts.Supervisor.ensure_started(draft.id, duel)

    # public_state exposes `available` as a LIST (the board renders it directly).
    before = Server.get_state(draft.id)
    hurt_id = before.available |> List.first() |> Map.get(:external_id)

    send(pid, {:injuries_refreshed, %{hurt_id => %{status: :out, label: "OUT", detail: "Knee"}}})
    # A synchronous call after the send guarantees the message was processed.
    after_state = Server.get_state(draft.id)
    flagged = Enum.filter(after_state.available, & &1.injury)

    assert length(flagged) == 1
    assert hd(flagged).injury.label == "OUT"
    # The pool itself is untouched — same players, same count.
    assert length(after_state.available) == length(before.available)
  end
end
