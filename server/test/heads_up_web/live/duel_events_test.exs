defmodule HeadsUpWeb.DuelEventsTest do
  @moduledoc """
  No more refreshing: a status change fans out to everyone seated, the
  website re-renders on it, and the phone's personal channel is yours alone.
  """
  use HeadsUpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Phoenix.ChannelTest, only: [subscribe_and_join: 3, assert_push: 2]
  require Phoenix.ChannelTest

  alias HeadsUp.{Accounts, Contests, Repo}
  alias HeadsUp.Contests.Events
  alias HeadsUp.Social.Friendship
  alias HeadsUpWeb.UserAuth

  @endpoint HeadsUpWeb.Endpoint

  setup %{conn: conn} do
    a = user("eva")
    b = user("evb")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
    %{conn: Phoenix.ConnTest.init_test_session(conn, %{}) |> UserAuth.log_in_web_user(a), a: a, b: b}
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  defp challenge(from, to) do
    {:ok, duel} =
      Contests.create_challenge(from, %{
        "sport" => "wnba",
        "opponent_id" => to.id,
        "roster_size" => 5,
        "draft_starts_at" => DateTime.utc_now() |> DateTime.add(1800, :second) |> DateTime.to_iso8601()
      })

    duel
  end

  test "every status change reaches both seats on their personal topics", %{a: a, b: b} do
    HeadsUpWeb.Endpoint.subscribe(Events.topic(a.id))
    HeadsUpWeb.Endpoint.subscribe(Events.topic(b.id))

    duel = challenge(a, b)
    id = duel.id
    # Creation itself: the opponent's list grows without a refresh.
    assert_receive %Phoenix.Socket.Broadcast{event: "duel_changed", payload: %{duel_id: ^id, status: "pending"}}

    {:ok, _} = Contests.accept_challenge(b, id)
    assert_receive %Phoenix.Socket.Broadcast{topic: "user:" <> _, event: "duel_changed", payload: %{duel_id: ^id, status: "accepted"}}

    {:ok, _} = Contests.cancel_drafting(id)
    assert_receive %Phoenix.Socket.Broadcast{event: "duel_changed", payload: %{duel_id: ^id, status: "cancelled"}}
  end

  test "the duels page shows ENTER ROOM the moment the rival accepts — no refresh", %{conn: conn, a: a, b: b} do
    duel = challenge(a, b)
    {:ok, view, html} = live(conn, ~p"/app/duels")
    assert html =~ "SENT"
    refute html =~ "ENTER ROOM"

    {:ok, _} = Contests.accept_challenge(b, duel.id)

    # The broadcast is async; render/1 processes the mailbox first.
    assert render(view) =~ "ENTER ROOM"
  end

  test "the duel detail page follows its duel live", %{conn: conn, a: a, b: b} do
    duel = challenge(a, b)
    {:ok, view, html} = live(conn, ~p"/app/duels/#{duel.id}")
    assert html =~ "PENDING" or html =~ "pending"

    {:ok, _} = Contests.accept_challenge(b, duel.id)
    assert render(view) =~ "ACCEPTED" or render(view) =~ "accepted"
  end

  test "the personal channel is yours alone", %{a: a, b: b} do
    {:ok, socket} = Phoenix.ChannelTest.connect(HeadsUpWeb.UserSocket, %{"token" => Accounts.create_user_api_token(a)})

    assert {:ok, _, _} = subscribe_and_join(socket, HeadsUpWeb.UserChannel, "user:#{a.id}")
    assert {:error, %{reason: "not yours"}} = subscribe_and_join(socket, HeadsUpWeb.UserChannel, "user:#{b.id}")

    # And it carries the fan-out to the phone.
    duel = challenge(b, a)
    id = duel.id
    assert_push "duel_changed", %{duel_id: ^id, status: "pending"}
  end
end
