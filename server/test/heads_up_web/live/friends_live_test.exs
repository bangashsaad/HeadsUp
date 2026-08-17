defmodule HeadsUpWeb.FriendsLiveTest do
  @moduledoc """
  The FRIENDS tab from the design drop: crew with records, the WANTS IN
  inbox, stranger search with request states, and private friend groups
  (create → edit mode → click-to-toggle membership).
  """
  use HeadsUpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias HeadsUp.{Accounts, Repo, Social}
  alias HeadsUp.Social.Friendship
  alias HeadsUpWeb.UserAuth

  setup %{conn: conn} do
    a = user("fla")
    b = user("flb")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
    %{conn: Phoenix.ConnTest.init_test_session(conn, %{}) |> UserAuth.log_in_web_user(a), a: a, b: b}
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  test "renders the crew with records, the requests inbox, and the groups card", %{conn: conn, a: a} do
    stranger = user("flknock")
    {:ok, _} = Social.send_friend_request(stranger, a.id)

    {:ok, _view, html} = live(conn, ~p"/app/friends")

    assert html =~ "YOUR CREW · 1"
    assert html =~ "flb"
    assert html =~ "0–0"
    assert html =~ "WANTS IN"
    assert html =~ "flknock"
    assert html =~ "GROUPS"
    assert html =~ "Groups are private"
    # Crew rows deep-link into the rivalry panel and the challenge builder.
    assert html =~ "/app/you?rival="
    assert html =~ "/app/new?rival="
  end

  test "accepting from the inbox makes friends; declining just clears it", %{conn: conn, a: a} do
    s1 = user("flreq1")
    s2 = user("flreq2")
    {:ok, _} = Social.send_friend_request(s1, a.id)
    {:ok, _} = Social.send_friend_request(s2, a.id)

    {:ok, view, _} = live(conn, ~p"/app/friends")
    reqs = Social.list_incoming_requests(a)
    r1 = Enum.find(reqs, &(&1.requester_id == s1.id))
    r2 = Enum.find(reqs, &(&1.requester_id == s2.id))

    render_click(view, "request-accept", %{"id" => to_string(r1.id)})
    assert Enum.any?(Social.list_friends(a), &(&1.id == s1.id))

    html = render_click(view, "request-decline", %{"id" => to_string(r2.id)})
    refute Enum.any?(Social.list_friends(a), &(&1.id == s2.id))
    assert html =~ "quiet inbox"
  end

  test "search shows strangers with SEND REQUEST, then SENT ✓", %{conn: conn} do
    _ = user("flstranger")

    {:ok, view, _} = live(conn, ~p"/app/friends")
    html = render_change(view, "search", %{"q" => "stranger"})

    assert html =~ "NOT IN YOUR CREW"
    assert html =~ "flstranger"
    assert html =~ "SEND REQUEST"
    assert html =~ "new here"

    target = Repo.get_by!(Accounts.User, username: "flstranger")
    html = render_click(view, "send-request", %{"id" => to_string(target.id)})

    assert html =~ "SENT ✓"
    assert [_] = Social.list_incoming_requests(target)
  end

  test "searching someone who already asked shows THEY ASKED — ACCEPT", %{conn: conn, a: a} do
    asker = user("flasker")
    {:ok, _} = Social.send_friend_request(asker, a.id)

    {:ok, view, _} = live(conn, ~p"/app/friends")
    html = render_change(view, "search", %{"q" => "flasker"})
    assert html =~ "THEY ASKED"

    [req] = Social.list_incoming_requests(a)
    render_click(view, "accept-search", %{"fid" => to_string(req.id)})
    assert Enum.any?(Social.list_friends(a), &(&1.id == asker.id))
  end

  test "a no-hit search says so", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/app/friends")
    html = render_change(view, "search", %{"q" => "zzghost"})
    assert html =~ "Nobody by that name"
  end

  test "create a group, click a friend in, click them out", %{conn: conn, a: a, b: b} do
    {:ok, view, _} = live(conn, ~p"/app/friends")

    # Created upcased, and the page drops straight into edit mode.
    html = render_submit(view, "create-group", %{"name" => "hoops crew"})
    assert html =~ "HOOPS CREW"
    assert html =~ "EDITING HOOPS CREW"
    assert html =~ "0 members"

    html = render_click(view, "toggle-member", %{"id" => to_string(b.id)})
    assert html =~ "1 member"
    [%{member_ids: ids}] = Social.list_friend_groups(a)
    assert ids == [b.id]

    html = render_click(view, "toggle-member", %{"id" => to_string(b.id)})
    assert html =~ "0 members"

    render_click(view, "edit-done", %{})
    refute render(view) =~ "EDITING HOOPS CREW"
  end

  test "tapping EDITING… again exits edit mode", %{conn: conn, a: a} do
    {:ok, group} = Social.create_friend_group(a, "CREW")
    {:ok, view, _} = live(conn, ~p"/app/friends")

    html = render_click(view, "edit-group", %{"id" => to_string(group.id)})
    assert html =~ "EDITING CREW"

    html = render_click(view, "edit-group", %{"id" => to_string(group.id)})
    refute html =~ "EDITING CREW"
  end

  test "duplicate group names are refused with a flash", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/app/friends")
    render_submit(view, "create-group", %{"name" => "WORK"})
    render_submit(view, "create-group", %{"name" => "work"})
    assert render(view) =~ "already have a group named WORK"
  end

  test "group tab filters the crew list", %{conn: conn, a: a, b: b} do
    c = user("flcrew2")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: c.id, status: "accepted"})
    {:ok, group} = Social.create_friend_group(a, "LEAGUE BOYS")
    {:ok, _} = Social.set_friend_group_members(a, group.id, [c.id])

    {:ok, view, html} = live(conn, ~p"/app/friends")
    assert html =~ "flb"
    assert html =~ "flcrew2"

    html = render_click(view, "tab", %{"id" => to_string(group.id)})
    assert html =~ "flcrew2"
    refute html =~ ~r/>flb</
    assert Repo.get_by(Accounts.User, username: b.username)
  end

  test "the sidebar carries FRIENDS with the request count", %{conn: conn, a: a} do
    stranger = user("flbadge")
    {:ok, _} = Social.send_friend_request(stranger, a.id)

    {:ok, _view, html} = live(conn, ~p"/app")
    assert html =~ "FRIENDS"
    assert html =~ "/app/friends"
  end

  test "/app/you?rival= opens that rivalry", %{conn: conn, b: b} do
    {:ok, _view, html} = live(conn, ~p"/app/you?rival=#{b.id}")
    assert html =~ "flb"
  end
end
