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
end
