defmodule BoutWeb.StatsController do
  use BoutWeb, :controller

  alias Bout.{Achievements, Stats}

  plug :put_view, json: BoutWeb.StatsJSON
  action_fallback BoutWeb.FallbackController

  # GET /api/me/stats — the viewer's record + head-to-head breakdown
  def me(conn, _params) do
    user = conn.assigns.current_user
    render(conn, :me, record: Stats.record_for(user.id), head_to_head: Stats.head_to_head(user.id))
  end

  # GET /api/me/achievements — the trophy catalog with progress
  def achievements(conn, _params) do
    user = conn.assigns.current_user
    render(conn, :achievements, achievements: Achievements.for_user(user.id))
  end

  # GET /api/leaderboard — standings among the viewer + their friends
  def leaderboard(conn, _params) do
    user = conn.assigns.current_user
    render(conn, :leaderboard, rows: Stats.leaderboard(user))
  end
end
