defmodule BoutWeb.HomeController do
  use BoutWeb, :controller

  alias Bout.Home

  plug :put_view, json: BoutWeb.HomeJSON
  action_fallback BoutWeb.FallbackController

  # GET /api/home — the dashboard buckets + record snapshot for the viewer
  def index(conn, _params) do
    user = conn.assigns.current_user
    render(conn, :index, summary: Home.summary(user), current_user_id: user.id)
  end
end
