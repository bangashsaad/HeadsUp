defmodule HeadsUpWeb.GameController do
  use HeadsUpWeb, :controller

  alias HeadsUp.Sports.{BoxScore, Schedule}
  alias HeadsUp.Sports.Espn.Client

  plug :put_view, json: HeadsUpWeb.GameJSON
  action_fallback HeadsUpWeb.FallbackController

  # GET /api/games/upcoming?sport=wnba
  def upcoming(conn, params) do
    sport = params["sport"] || "wnba"
    {:ok, games} = Schedule.upcoming(sport)
    render(conn, :upcoming, games: games)
  end

  # GET /api/games/:event_id/boxscore?sport=wnba  — live/final box score + fantasy
  def boxscore(conn, %{"event_id" => event_id} = params) do
    sport = params["sport"] || "wnba"

    cond do
      not Client.supported?(sport) ->
        {:error, "sport must be one of: #{Enum.join(Client.leagues(), ", ")}"}

      true ->
        case BoxScore.for_event(sport, event_id) do
          {:ok, box} ->
            render(conn, :boxscore, box: box)

          {:error, _reason} ->
            conn |> put_status(:bad_gateway) |> json(%{error: "box score unavailable"})
        end
    end
  end
end
