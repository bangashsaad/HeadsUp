defmodule HeadsUp.Sports.Espn.ClientTest do
  # async: false — each test installs its own Req.Test stub and swaps app env.
  use ExUnit.Case, async: false

  alias HeadsUp.Sports.Espn.Client

  @stub HeadsUp.Sports.Espn.ClientTest.Stub

  setup do
    prev = Application.get_env(:heads_up, HeadsUp.Sports.Espn)

    Application.put_env(:heads_up, HeadsUp.Sports.Espn,
      base_url: "https://espn.test/apis/wnba",
      # retry: false so a stubbed 500/transport error returns immediately
      req_options: [plug: {Req.Test, @stub}, retry: false]
    )

    on_exit(fn -> Application.put_env(:heads_up, HeadsUp.Sports.Espn, prev) end)
    :ok
  end

  test "scoreboard/1 hits /scoreboard with the date param and returns the decoded body" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/apis/wnba/scoreboard"
      assert conn.query_string =~ "dates=20260628"
      Req.Test.json(conn, %{"events" => [%{"id" => "1"}]})
    end)

    assert {:ok, %{"events" => [%{"id" => "1"}]}} = Client.scoreboard("20260628")
  end

  test "summary/1 passes the event id" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/apis/wnba/summary"
      assert conn.query_string =~ "event=401857030"
      Req.Test.json(conn, %{"boxscore" => %{}})
    end)

    assert {:ok, %{"boxscore" => %{}}} = Client.summary(401_857_030)
  end

  test "roster/1 builds the team path" do
    Req.Test.stub(@stub, fn conn ->
      assert conn.request_path == "/apis/wnba/teams/3/roster"
      Req.Test.json(conn, %{"athletes" => []})
    end)

    assert {:ok, %{"athletes" => []}} = Client.roster(3)
  end

  test "an HTTP error status becomes {:error, {:http, status}}" do
    Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)
    assert {:error, {:http, 500}} = Client.scoreboard("20260628")
  end

  test "a transport failure becomes {:error, {:transport, _}}" do
    Req.Test.stub(@stub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
    assert {:error, {:transport, _}} = Client.teams()
  end
end
