defmodule HeadsUpWeb.UserController do
  use HeadsUpWeb, :controller

  alias HeadsUp.Social

  plug :put_view, json: HeadsUpWeb.PublicUserJSON
  action_fallback HeadsUpWeb.FallbackController

  # GET /api/users/search?q=...
  def search(conn, params) do
    query = Map.get(params, "q", "")
    results = Social.search_users(query, conn.assigns.current_user)
    render(conn, :search, results: results)
  end
end
