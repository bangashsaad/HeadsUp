defmodule HeadsUpWeb.WebScreensTest do
  @moduledoc """
  The web app's Phase-1 screens, driven end to end: duels (accept/decline),
  the challenge form (same payload as the phone), live chat over PubSub,
  and the account surface.
  """
  use HeadsUpWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias HeadsUp.{Accounts, Contests, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Social.Friendship
  alias HeadsUpWeb.UserAuth

  setup %{conn: conn} do
    # NewChallengeLive's mount probes Season, which caches per sport for an
    # hour in persistent_term. A fail-open probe cached HERE would leak into
    # season_test's positively-gated assertions — clear ours on the way out.
    on_exit(fn ->
      for sport <- ~w(wnba nba mlb nfl) do
        :persistent_term.erase({HeadsUp.Sports.Season, sport})
      end
    end)

    a = user("weba2")
    b = user("webb2")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
    %{conn: log_in(conn, a), a: a, b: b}
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    # The signup grant both front doors give — a stake test needs a wallet.
    _ = HeadsUp.Coins.grant_signup(u.id)
    u
  end

  defp log_in(conn, user) do
    conn |> Phoenix.ConnTest.init_test_session(%{}) |> UserAuth.log_in_web_user(user)
  end

  defp challenge_of(user), do: user |> Contests.list_duels() |> List.first()

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

  describe "duels screen" do
    test "an incoming challenge shows accept/decline and accepting flips it live", %{conn: conn, a: a, b: b} do
      # b challenges a, so a (our session) is the one who answers.
      challenge(b, a)

      {:ok, view, html} = live(conn, ~p"/app/duels")
      assert html =~ "RESPOND"
      assert html =~ "ACCEPT"

      duel = challenge_of(a)
      render_click(view, "accept", %{"id" => to_string(duel.id)})

      assert Repo.get(Duel, duel.id).status == "accepted"
      assert render(view) =~ "ENTER ROOM"
    end

    test "declining ends it", %{conn: conn, a: a, b: b} do
      duel = challenge(b, a)
      {:ok, view, _} = live(conn, ~p"/app/duels")

      render_click(view, "decline", %{"id" => to_string(duel.id)})
      assert Repo.get(Duel, duel.id).status == "declined"
    end

    test "the sender can cancel a pending challenge", %{conn: conn, a: a, b: b} do
      duel = challenge(a, b)
      {:ok, view, html} = live(conn, ~p"/app/duels")

      assert html =~ "SENT"
      render_click(view, "cancel", %{"id" => to_string(duel.id)})
      assert Repo.get(Duel, duel.id).status == "cancelled"
    end
  end

  describe "new challenge screen" do
    test "sends the same challenge the phone would", %{conn: conn, a: a, b: b} do
      {:ok, view, html} = live(conn, ~p"/app/new")

      # The app's values, verbatim.
      assert html =~ "5 SLOTS"
      assert html =~ "15 sec"
      refute html =~ "3 SLOTS"

      render_click(view, "rival", %{"id" => to_string(b.id)})
      render_click(view, "roster", %{"n" => "7"})
      render_click(view, "stake", %{"n" => "25"})
      render_click(view, "clock", %{"n" => "60"})
      render_click(view, "send", %{})

      duel = challenge_of(a)
      assert duel.challenger_id == a.id
      assert duel.opponent_id == b.id
      assert duel.roster_size == 7
      assert duel.stake_coins == 25
      assert duel.pick_clock_seconds == 60
      assert duel.lineup_template == "wnba_7"
    end

    test "refuses to send with nobody picked", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/app/new")
      html = render_click(view, "send", %{})
      assert html =~ "Pick at least one rival"
    end
  end

  describe "trash talk on the web" do
    test "a message posted via the context reaches the live screen over PubSub", %{conn: conn, a: a, b: b} do
      duel = challenge(a, b)
      {:ok, _} = Contests.accept_challenge(b, duel.id)

      {:ok, view, _html} = live(conn, ~p"/app/live/#{duel.id}")

      # b talks (as the phone would, through the same context function).
      {:ok, _} = Contests.post_message(b, duel.id, "Fourth quarter exists my guy")

      assert render(view) =~ "Fourth quarter exists my guy"
    end

    test "sending from the web posts through the same path", %{conn: conn, a: a, b: b} do
      duel = challenge(a, b)
      {:ok, _} = Contests.accept_challenge(b, duel.id)

      {:ok, view, _html} = live(conn, ~p"/app/live/#{duel.id}")
      render_submit(view, "send", %{"body" => "Scoreboard."})

      {:ok, thread} = Contests.list_messages(a, duel.id)
      assert Enum.any?(thread, &(&1.body == "Scoreboard."))
    end
  end

  describe "the you screen" do
    test "renders record, standings, and the account controls", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/app/you")

      assert html =~ "YOUR CREW"
      assert html =~ "HOW YOU WIN"
      assert html =~ "CHANGE PASSWORD"
      assert html =~ "DELETE ACCOUNT"
      assert html =~ "SIGN OUT"
    end

    test "change password round-trips", %{conn: conn, a: a} do
      {:ok, view, _} = live(conn, ~p"/app/you")

      render_click(view, "danger", %{"which" => "password"})
      render_submit(view, "change-password", %{"current" => "password123", "new" => "newpassword456"})

      assert HeadsUp.Accounts.get_user_by_email_and_password(a.email, "newpassword456")
    end
  end

  describe "games screen" do
    test "renders games only — the design's scoreboard has no player-pool tab", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/app/games")
      assert html =~ "SCOREBOARD"
      refute html =~ "PLAYER POOL"
    end
  end
end
