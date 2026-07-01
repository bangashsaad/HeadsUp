defmodule HeadsUpWeb.PlayerController do
  use HeadsUpWeb, :controller

  alias HeadsUp.Sports
  alias HeadsUp.Sports.Profile

  plug :put_view, json: HeadsUpWeb.PlayerJSON
  action_fallback HeadsUpWeb.FallbackController

  # GET /api/players?sport=nfl&q=&position=
  def index(conn, params) do
    sport = params["sport"]

    if sport in Sports.sports() do
      players =
        Sports.list_players(sport, q: params["q"], position: params["position"], team: params["team"])

      render(conn, :index, players: players, positions: Sports.list_positions(sport))
    else
      {:error, "sport must be one of: #{Enum.join(Sports.sports(), ", ")}"}
    end
  end

  # GET /api/players/search?q=  — cross-sport search over real ESPN players
  def search(conn, params) do
    players = Sports.search_players(params["q"] || "")
    render(conn, :search, players: players)
  end

  # GET /api/players/:id/profile  — season averages + fantasy game log
  def profile(conn, %{"id" => id}) do
    case Sports.get_player(id) do
      nil -> {:error, :not_found}
      player -> render(conn, :profile, profile: elem(Profile.for_player(player), 1))
    end
  end
end
