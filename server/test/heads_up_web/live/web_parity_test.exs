defmodule HeadsUpWeb.WebParityTest do
  @moduledoc """
  The web must enforce what the phone enforces. These pin the three loop gaps:
  the verify-email gate (the API had it, the LiveViews didn't), the friend-
  requests inbox, and counter being 1v1-only.
  """
  use HeadsUpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias HeadsUp.{Accounts, Contests, Repo}
  alias HeadsUp.Social
  alias HeadsUp.Social.Friendship
  alias HeadsUpWeb.UserAuth

  setup %{conn: conn} do
    a = user("para")
    b = user("parb")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
    %{conn: Phoenix.ConnTest.init_test_session(conn, %{}) |> UserAuth.log_in_web_user(a), a: a, b: b}
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  describe "the verify-email gate on the web" do
    setup do
      # The suite runs with the gate off (same as the API tests); flip it on
      # for exactly these assertions.
      prev = Application.get_env(:heads_up, :require_verified_email)
      Application.put_env(:heads_up, :require_verified_email, true)
      on_exit(fn -> Application.put_env(:heads_up, :require_verified_email, prev) end)
      :ok
    end

    test "an unverified browser cannot send a challenge — it is bounced to /app/verify", %{conn: conn, b: b} do
      {:ok, view, _html} = live(conn, ~p"/app/new")

      render_click(view, "rival", %{"id" => to_string(b.id)})
      render_click(view, "send", %{})

      assert_redirect(view, "/app/verify")
      assert Contests.list_duels(Repo.get!(Accounts.User, b.id)) == []
    end

    test "an unverified browser cannot accept — same bounce", %{conn: conn, a: a, b: b} do
      {:ok, duel} =
        Contests.create_challenge(b, %{
          "sport" => "wnba",
          "opponent_id" => a.id,
          "roster_size" => 5,
          "draft_starts_at" => DateTime.utc_now() |> DateTime.add(1800, :second) |> DateTime.to_iso8601()
        })

      {:ok, view, _html} = live(conn, ~p"/app/duels")
      render_click(view, "accept", %{"id" => to_string(duel.id)})

      assert_redirect(view, "/app/verify")
      assert Repo.get!(Contests.Duel, duel.id).status == "pending"
    end

    test "the verify page renders and rejects a wrong code", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/app/verify")
      assert html =~ "VERIFY YOUR EMAIL"

      html = render_submit(view, "confirm", %{"code" => "000000"})
      assert html =~ "isn&#39;t right" or html =~ "isn't right"
    end

    test "a verified user is sent straight back to the app", %{conn: conn, a: a} do
      a
      |> Ecto.Changeset.change(email_verified_at: DateTime.utc_now() |> DateTime.truncate(:second))
      |> Repo.update!()

      assert {:error, {:redirect, %{to: "/app"}}} = live(conn, ~p"/app/verify")
    end
  end

  describe "friend requests on the web" do
    test "an incoming request renders and accepting makes friends", %{conn: conn, a: a} do
      stranger = user("parstranger")
      {:ok, _} = Social.send_friend_request(stranger, a.id)

      {:ok, view, html} = live(conn, ~p"/app/you")
      assert html =~ "WANTS IN"
      assert html =~ "parstranger"

      [req] = Social.list_incoming_requests(a)
      render_click(view, "request-accept", %{"id" => to_string(req.id)})

      assert Enum.any?(Social.list_friends(a), &(&1.id == stranger.id))
      refute render(view) =~ "WANTS IN"
    end

    test "declining removes the request without making friends", %{conn: conn, a: a} do
      stranger = user("parstranger2")
      {:ok, _} = Social.send_friend_request(stranger, a.id)

      {:ok, view, _html} = live(conn, ~p"/app/you")
      [req] = Social.list_incoming_requests(a)
      render_click(view, "request-decline", %{"id" => to_string(req.id)})

      assert Social.list_incoming_requests(a) == []
      refute Enum.any?(Social.list_friends(a), &(&1.id == stranger.id))
    end
  end

  describe "counter parity" do
    test "a group challenge offers no COUNTER (server and phone are 1v1-only)", %{conn: conn, a: a, b: b} do
      c = user("parc")
      Repo.insert!(%Friendship{requester_id: b.id, addressee_id: c.id, status: "accepted"})
      Repo.insert!(%Friendship{requester_id: a.id, addressee_id: c.id, status: "accepted"})

      {:ok, _duel} =
        Contests.create_challenge(b, %{
          "sport" => "wnba",
          "opponent_ids" => [a.id, c.id],
          "roster_size" => 5,
          "draft_starts_at" => DateTime.utc_now() |> DateTime.add(1800, :second) |> DateTime.to_iso8601()
        })

      {:ok, _view, html} = live(conn, ~p"/app/duels")

      assert html =~ "RESPOND"
      refute html =~ ">COUNTER<"
    end
  end

  describe "friend search on the web" do
    test "matches a fragment anywhere in the username and shows the sent state", %{conn: conn} do
      _target = user("nyelfragment")

      {:ok, view, _html} = live(conn, ~p"/app/you")
      render_click(view, "add-friend-toggle", %{})

      # The bug: prefix-only matching made this exact search return nothing.
      html = render_change(view, "friend-search", %{"q" => "fragment"})
      assert html =~ "nyelfragment"

      target = Repo.get_by!(Accounts.User, username: "nyelfragment")
      html = render_click(view, "friend-request", %{"id" => to_string(target.id)})

      assert html =~ "SENT ✓"
      assert Enum.any?(Social.list_incoming_requests(target), & &1)
    end

    test "an empty result says so instead of showing nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/app/you")
      render_click(view, "add-friend-toggle", %{})

      html = render_change(view, "friend-search", %{"q" => "zzznobody"})
      assert html =~ "Nobody by that name"
    end
  end
end
