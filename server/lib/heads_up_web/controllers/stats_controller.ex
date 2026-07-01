defmodule HeadsUpWeb.StatsController do
  use HeadsUpWeb, :controller

  alias HeadsUp.Stats

  plug :put_view, json: HeadsUpWeb.StatsJSON
  action_fallback HeadsUpWeb.FallbackController

  # GET /api/me/stats — the viewer's record + head-to-head breakdown
  def me(conn, _params) do
    user = conn.assigns.current_user
    render(conn, :me, record: Stats.record_for(user.id), head_to_head: Stats.head_to_head(user.id))
  end

  # GET /api/leaderboard — standings among the viewer + their friends
  def leaderboard(conn, _params) do
    user = conn.assigns.current_user
    render(conn, :leaderboard, rows: Stats.leaderboard(user))
  end
end
