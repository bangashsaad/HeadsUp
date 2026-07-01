defmodule HeadsUpWeb.HomeController do
  use HeadsUpWeb, :controller

  alias HeadsUp.Home

  plug :put_view, json: HeadsUpWeb.HomeJSON
  action_fallback HeadsUpWeb.FallbackController

  # GET /api/home — the dashboard buckets + record snapshot for the viewer
  def index(conn, _params) do
    user = conn.assigns.current_user
    render(conn, :index, summary: Home.summary(user), current_user_id: user.id)
  end
end
