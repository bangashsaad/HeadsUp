defmodule HeadsUpWeb.GameController do
  use HeadsUpWeb, :controller

  alias HeadsUp.Sports.Schedule

  plug :put_view, json: HeadsUpWeb.GameJSON
  action_fallback HeadsUpWeb.FallbackController

  # GET /api/games/upcoming?sport=wnba
  def upcoming(conn, params) do
    sport = params["sport"] || "wnba"
    {:ok, games} = Schedule.upcoming(sport)
    render(conn, :upcoming, games: games)
  end
end
