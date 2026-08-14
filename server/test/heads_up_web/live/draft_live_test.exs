defmodule HeadsUpWeb.DraftLiveTest do
  @moduledoc """
  The Phase 0 question: can a browser sit in the same live draft as a phone,
  driven by the same GenServer, with no second engine?
  """
  use HeadsUpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias HeadsUp.{Accounts, Contests, Drafts, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Drafts.{Server, Supervisor}
  alias HeadsUp.Social.Friendship
  alias HeadsUp.Sports.Player
  alias HeadsUpWeb.UserAuth

  setup %{conn: conn} do
    a = user("weba")
    b = user("webb")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
    seed_pool()

    {:ok, duel} =
      Contests.create_challenge(a, %{
        "sport" => "wnba",
        "opponent_id" => b.id,
        "roster_size" => 5,
        "draft_starts_at" => DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.to_iso8601()
      })

    {:ok, _} = Contests.accept_challenge(b, duel.id)
    {:ok, draft} = Drafts.get_or_create_draft_for_duel(Repo.get(Duel, duel.id))
    {:ok, _pid} = Supervisor.ensure_started(draft.id, Repo.get(Duel, duel.id))

    %{conn: log_in(conn, a), a: a, b: b, duel: duel, draft: draft}
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  defp log_in(conn, user) do
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> UserAuth.log_in_web_user(user)
  end

  defp seed_pool do
    for {pos, pi} <- Enum.with_index(~w(G G F F C)), n <- 1..4 do
      Repo.insert!(%Player{
        sport: "wnba",
        external_id: "#{8_400_000 + pi * 10 + n}",
        name: "#{pos} Player #{pi}#{n}",
        team: "TST",
        position: pos,
        projection: 100.0 - pi * 10 - n
      })
    end
  end

  test "an unauthenticated browser is sent to sign in", %{duel: duel} do
    conn = Phoenix.ConnTest.build_conn()
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/app/draft/#{duel.id}")
  end

  test "someone else's draft is not joinable", %{duel: duel, conn: conn} do
    stranger = user("webstranger")
    conn = log_in(conn, stranger)

    assert {:error, {:redirect, %{to: "/app"}}} = live(conn, ~p"/app/draft/#{duel.id}")
  end

  test "the lobby renders both players and readying up is broadcast", %{conn: conn, duel: duel, draft: draft, a: a, b: b} do
    {:ok, view, html} = live(conn, ~p"/app/draft/#{duel.id}")

    assert html =~ "READY"
    assert html =~ "weba"
    assert html =~ "webb"
    assert html =~ "I&#39;M READY" or html =~ "I'M READY"

    # Readying from the browser must reach the same engine the phones use.
    render_click(view, "ready", %{})
    assert Server.get_state(draft.id).ready[a.id]

    # And the other player readying (as a phone would) must reach the browser.
    Server.ready(draft.id, b.id)
    assert render(view) =~ "YOUR PICK" or render(view) =~ "PICKING"
  end

  test "a pick made on a phone appears in the browser without a refresh", %{conn: conn, duel: duel, draft: draft, a: a, b: b} do
    {:ok, view, _html} = live(conn, ~p"/app/draft/#{duel.id}")

    Server.ready(draft.id, a.id)
    Server.ready(draft.id, b.id)

    state = Server.get_state(draft.id)
    picker = state.current_picker_id
    player = state.available |> Enum.sort_by(&(-&1.projection)) |> hd()

    # Whoever is on the clock picks through the engine, exactly as the channel
    # would. The browser is a subscriber, so it should just… know.
    Server.make_pick(draft.id, picker, player.id)

    html = render(view)
    # The board shows the pick as a last-name slot chip.
    assert html =~ (player.name |> String.split() |> List.last())
    # And the picked player has left the pool list.
    refute html =~ ">#{player.name}<"
    assert Server.get_state(draft.id).pick_number == 2
  end

  test "the browser can make its own pick when it is on the clock", %{conn: conn, duel: duel, draft: draft, a: a, b: b} do
    {:ok, view, _html} = live(conn, ~p"/app/draft/#{duel.id}")

    Server.ready(draft.id, a.id)
    Server.ready(draft.id, b.id)

    state = Server.get_state(draft.id)

    if state.current_picker_id == a.id do
      player = state.available |> Enum.sort_by(&(-&1.projection)) |> hd()
      render_click(view, "pick", %{"player-id" => to_string(player.id)})

      after_pick = Server.get_state(draft.id)
      assert after_pick.pick_number == 2
      refute Enum.any?(after_pick.available, &(&1.id == player.id))
    end
  end

  test "search narrows the board", %{conn: conn, duel: duel, draft: draft, a: a, b: b} do
    {:ok, view, _html} = live(conn, ~p"/app/draft/#{duel.id}")

    Server.ready(draft.id, a.id)
    Server.ready(draft.id, b.id)

    html = render_change(view, "search", %{"q" => "zzzznotaplayer"})
    assert html =~ "No players match"
  end
end
