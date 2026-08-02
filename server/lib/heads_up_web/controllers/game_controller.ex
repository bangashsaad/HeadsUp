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

  # GET /api/sports/:sport/slates — what a duel can be scoped to.
  #
  # Two shapes behind one endpoint: football answers with WEEKS (its teams play
  # once, so a single night is two teams), everything else with ET DAYS. `kind`
  # tells the client which it got; an empty list (feed down or unsupported
  # sport) hides the picker and the server defaults the slate.
  def slates(conn, %{"sport" => sport}) do
    alias HeadsUp.Sports.Slate

    if Slate.week_shaped?(sport) do
      json(conn, %{sport: sport, kind: "week", slates: week_slates(sport)})
    else
      json(conn, %{sport: sport, kind: "day", slates: day_slates(sport)})
    end
  end

  defp day_slates(sport) do
    case HeadsUp.Sports.Slate.upcoming(sport) do
      {:ok, days} ->
        Enum.map(days, fn d ->
          %{
            date: d.date,
            games: d.games,
            upcoming: d.upcoming,
            # Draftable bodies on that slate. The client mirrors the
            # create-time guard (roster x drafters x 2) to grey out roster
            # sizes the night can't support, instead of failing on send.
            players: HeadsUp.Contests.slate_player_count(sport, d.upcoming_teams)
          }
        end)

      {:error, _} ->
        []
    end
  end

  defp week_slates(sport) do
    case HeadsUp.Sports.Slate.weeks(sport) do
      {:ok, weeks} ->
        Enum.map(weeks, fn w ->
          %{
            key: w.key,
            label: w.label,
            week: w.week,
            season_type: w.season_type,
            # Every ET day the week has games on — the first is what a client
            # shows as the start, and the last is when the duel settles.
            dates: w.dates,
            date: List.first(w.dates),
            last_date: List.last(w.dates),
            games: w.games,
            upcoming: w.upcoming,
            players: HeadsUp.Contests.slate_player_count(sport, w.upcoming_teams)
          }
        end)

      {:error, _} ->
        []
    end
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
