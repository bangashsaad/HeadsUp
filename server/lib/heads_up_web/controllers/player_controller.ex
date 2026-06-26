defmodule HeadsUpWeb.PlayerController do
  use HeadsUpWeb, :controller

  alias HeadsUp.Sports

  plug :put_view, json: HeadsUpWeb.PlayerJSON
  action_fallback HeadsUpWeb.FallbackController

  # GET /api/players?sport=nfl&q=&position=
  def index(conn, params) do
    sport = params["sport"]

    if sport in Sports.sports() do
      players =
        Sports.list_players(sport, q: params["q"], position: params["position"])

      render(conn, :index, players: players, positions: Sports.list_positions(sport))
    else
      {:error, "sport must be one of: #{Enum.join(Sports.sports(), ", ")}"}
    end
  end
end
