defmodule HeadsUpWeb.GameController do
  use HeadsUpWeb, :controller

  alias HeadsUp.Sports.{BoxScore, Schedule}
  alias HeadsUp.Sports.Espn.Client

  plug :put_view, json: HeadsUpWeb.GameJSON
  action_fallback HeadsUpWeb.FallbackController

  # GET /api/games/upcoming?sport=wnba
  # GET /api/sports/status — which sports are playable right now (season
  # window + real pool). Drives the challenge form's sport picker.
  def season(conn, _params) do
    json(conn, %{sports: HeadsUp.Sports.Season.statuses()})
  end

  def upcoming(conn, params) do
    sport = params["sport"] || "wnba"
    {:ok, games} = Schedule.upcoming(sport)
    render(conn, :upcoming, games: games)
  end

  # GET /api/games/scoreboard?sport=wnba&date=2026-07-04 — one ET day, any day
  # (past dates give finished games whose box scores are still browsable).
  def scoreboard(conn, %{"date" => date_str} = params) do
    sport = params["sport"] || "wnba"

    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        {:ok, games} = Schedule.on_date(sport, date)
        render(conn, :upcoming, games: games)

      {:error, _} ->
        {:error, "date must be YYYY-MM-DD"}
    end
  end

  def scoreboard(_conn, _params), do: {:error, "date is required (YYYY-MM-DD)"}

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
