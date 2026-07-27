defmodule HeadsUp.Sports.Espn.ClientTest do
  # async: false — each test installs its own Req.Test stub and swaps app env.
  use ExUnit.Case, async: false

  alias HeadsUp.Sports.Espn.Client

  @stub HeadsUp.Sports.Espn.ClientTest.Stub

  setup do
    prev = Application.get_env(:heads_up, HeadsUp.Sports.Espn)

    Application.put_env(:heads_up, HeadsUp.Sports.Espn,
      site_host: "https://espn.test/site",
      web_host: "https://espn.test/web",
      # retry: false so a stubbed 500/transport error returns immediately
      req_options: [plug: {Req.Test, @stub}, retry: false]
    )

    on_exit(fn -> Application.put_env(:heads_up, HeadsUp.Sports.Espn, prev) end)
    :ok
  end

  test "scoreboard hits the league scoreboard with the date param" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/site/basketball/wnba/scoreboard"
      assert conn.query_string =~ "dates=20260628"
      Req.Test.json(conn, %{"events" => [%{"id" => "1"}]})
    end)

    assert {:ok, %{"events" => [%{"id" => "1"}]}} = Client.scoreboard("wnba", "20260628")
  end

  test "the sport selects the ESPN league path (mlb -> baseball/mlb)" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/site/baseball/mlb/scoreboard"
      Req.Test.json(conn, %{"events" => []})
    end)

    assert {:ok, %{"events" => []}} = Client.scoreboard("mlb", "20260628")
  end

  test "gamelog uses the web host + athlete path" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/web/baseball/mlb/athletes/41172/gamelog"
      Req.Test.json(conn, %{"labels" => []})
    end)

    assert {:ok, %{"labels" => []}} = Client.gamelog("mlb", 41_172)
  end

  test "summary passes the event id" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/site/basketball/wnba/summary"
      assert conn.query_string =~ "event=401857030"
      Req.Test.json(conn, %{"boxscore" => %{}})
    end)

    assert {:ok, %{"boxscore" => %{}}} = Client.summary("wnba", 401_857_030)
  end

  test "roster builds the team path" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/site/basketball/wnba/teams/3/roster"
      Req.Test.json(conn, %{"athletes" => []})
    end)

    assert {:ok, %{"athletes" => []}} = Client.roster("wnba", 3)
  end

  test "an unknown sport raises (programmer error, not a feed error)" do
    assert_raise ArgumentError, fn -> Client.scoreboard("cricket", "20260628") end
  end

  test "an HTTP error status becomes {:error, {:http, status}}" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)
    assert {:error, {:http, 500}} = Client.scoreboard("wnba", "20260628")
  end

  test "a transport failure becomes {:error, {:transport, _}}" do
    Req.Test.stub(@stub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
    assert {:error, {:transport, _}} = Client.teams("wnba")
  end
end
