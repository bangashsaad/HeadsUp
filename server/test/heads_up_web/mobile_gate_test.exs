defmodule HeadsUpWeb.MobileGateTest do
  @moduledoc """
  Phones get the app-gate page instead of the desktop site; computers,
  iPads, and devices that chose HARD MODE pass untouched. Landing and
  legal pages stay reachable on anything.
  """
  use HeadsUpWeb.ConnCase, async: true

  @iphone "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
  @android_phone "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Mobile Safari/537.36"
  @android_tablet "Mozilla/5.0 (Linux; Android 14; SM-X710) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36"
  @ipad "Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
  @desktop "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

  defp with_ua(conn, ua), do: Plug.Conn.put_req_header(conn, "user-agent", ua)

  describe "who gets gated" do
    test "an iPhone hitting login is sent to the gate", %{conn: conn} do
      conn = conn |> with_ua(@iphone) |> get(~p"/login")
      assert redirected_to(conn) == "/get-the-app"
    end

    test "an Android phone too", %{conn: conn} do
      conn = conn |> with_ua(@android_phone) |> get(~p"/signup")
      assert redirected_to(conn) == "/get-the-app"
    end

    test "an iPhone hitting the app is gated before auth gets a word in", %{conn: conn} do
      conn = conn |> with_ua(@iphone) |> get(~p"/app")
      assert redirected_to(conn) == "/get-the-app"
    end

    test "desktops, iPads, and Android tablets pass", %{conn: conn} do
      for ua <- [@desktop, @ipad, @android_tablet] do
        conn = Phoenix.ConnTest.build_conn() |> with_ua(ua) |> get(~p"/login")
        assert html_response(conn, 200) =~ "Sign in"
      end
    end

    test "a phone's first touch of the landing is the gate", %{conn: conn} do
      conn = conn |> with_ua(@iphone) |> get(~p"/")
      assert redirected_to(conn) == "/get-the-app"
    end

    test "crawlers with phone user-agents still see the real landing", %{conn: conn} do
      googlebot =
        "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Mobile Safari/537.36 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"

      assert conn |> with_ua(googlebot) |> get(~p"/") |> html_response(200)
    end

    test "legal pages stay reachable on a phone", %{conn: conn} do
      assert conn |> with_ua(@iphone) |> get(~p"/privacy") |> html_response(200)
    end

    test "the escaped-hatch cookie opens the landing back up", %{conn: conn} do
      conn =
        conn
        |> with_ua(@iphone)
        |> Plug.Test.put_req_cookie(HeadsUpWeb.MobileGate.bypass_cookie(), "1")
        |> get(~p"/")

      assert html_response(conn, 200)
    end
  end

  describe "the gate page" do
    test "invite-only state without a TestFlight link", %{conn: conn} do
      html = conn |> with_ua(@iphone) |> get(~p"/get-the-app") |> html_response(200)
      assert html =~ "YOUR RIVALS"
      assert html =~ "BETA · INVITE ONLY"
      assert html =~ "I ALREADY HAVE IT — OPEN THE APP"
      assert html =~ "winners hand them out"
      assert html =~ "SURE ABOUT THAT?"
      assert html =~ "HARD MODE"
      refute html =~ "TestFlight."
    end

    test "normal state once the TestFlight link exists", %{conn: conn} do
      prev = Application.get_env(:heads_up, :testflight_url)
      Application.put_env(:heads_up, :testflight_url, "https://testflight.apple.com/join/TEST123")
      on_exit(fn -> Application.put_env(:heads_up, :testflight_url, prev) end)

      html = conn |> with_ua(@iphone) |> get(~p"/get-the-app") |> html_response(200)
      assert html =~ "DUELS ARE LIVE"
      assert html =~ "OPEN THE APP →"
      assert html =~ "Same button lands on TestFlight"
      assert html =~ "testflight.apple.com/join/TEST123"
    end
  end

  describe "the escape hatch" do
    test "HARD MODE sets the cookie and the site opens up", %{conn: conn} do
      conn = conn |> with_ua(@iphone) |> get(~p"/get-the-app/continue")
      assert redirected_to(conn) == "/app"
      assert conn.resp_cookies[HeadsUpWeb.MobileGate.bypass_cookie()].value == "1"
      # Session-scoped: no max_age, so the gate is back once the browser closes.
      refute Map.has_key?(conn.resp_cookies[HeadsUpWeb.MobileGate.bypass_cookie()], :max_age)

      # Same phone, cookie carried: no more gate (auth takes over instead).
      conn =
        Phoenix.ConnTest.build_conn()
        |> with_ua(@iphone)
        |> Plug.Test.put_req_cookie(HeadsUpWeb.MobileGate.bypass_cookie(), "1")
        |> get(~p"/login")

      assert html_response(conn, 200) =~ "Sign in"
    end
  end

  describe "/install" do
    test "redirects to the gate until the TestFlight link exists", %{conn: conn} do
      conn = conn |> with_ua(@iphone) |> get(~p"/install")
      assert redirected_to(conn) == "/get-the-app"
    end

    test "redirects straight to TestFlight once it does", %{conn: conn} do
      prev = Application.get_env(:heads_up, :testflight_url)
      Application.put_env(:heads_up, :testflight_url, "https://testflight.apple.com/join/TEST123")
      on_exit(fn -> Application.put_env(:heads_up, :testflight_url, prev) end)

      conn = get(conn, ~p"/install")
      assert redirected_to(conn) == "https://testflight.apple.com/join/TEST123"
    end
  end

  describe "the retired 180-day cookie" do
    test "no longer opens the site — every phone is back at the gate", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("user-agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) Mobile/15E148 Safari/604.1")
        |> Plug.Test.put_req_cookie("mobile_web_ok", "1")
        |> get(~p"/")

      assert redirected_to(conn) == "/get-the-app"
    end

    test "the in-page backstop ships on the landing and is path-guarded", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ "location.replace('/get-the-app')"
      # The script itself decides by path, so the (ungated) legal pages are safe
      # even though they share the root layout.
      assert html =~ "login|signup|app|forgot-password|reset-password"
      assert html =~ "navigator.maxTouchPoints>1"
    end
  end
end
