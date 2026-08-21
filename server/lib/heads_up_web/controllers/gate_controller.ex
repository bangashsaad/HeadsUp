defmodule HeadsUpWeb.GateController do
  use HeadsUpWeb, :controller

  @doc """
  The phone gate, from Saad's App Gate design drop: what a phone sees instead
  of the desktop site. Two states off one template — the TestFlight public
  link exists (OPEN THE APP falls back to it) or it doesn't yet (invite-only
  copy, deep-link-only button). The bottom ticker is the app shell's real
  cached slate; on a dead night the bar simply doesn't render.
  """
  def show(conn, _params) do
    conn
    |> put_layout(false)
    |> render(:show,
      testflight_url: Application.get_env(:heads_up, :testflight_url),
      ticker: HeadsUpWeb.ShellHook.game_ticker()
    )
  end

  @doc """
  The escape hatch's HARD MODE choice: hand over the desktop site for this
  browser session only (no max_age ⇒ the cookie dies with the browser, and
  the gate is back next visit). A cookie rather than the design's
  localStorage note — the server picks gate-vs-site before any JavaScript.
  """
  def continue(conn, _params) do
    conn
    |> put_resp_cookie(HeadsUpWeb.MobileGate.bypass_cookie(), "1", same_site: "Lax")
    |> redirect(to: "/app")
  end
end
