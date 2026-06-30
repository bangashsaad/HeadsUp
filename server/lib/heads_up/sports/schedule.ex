defmodule HeadsUp.Sports.Schedule do
  @moduledoc """
  Upcoming games from the live ESPN scoreboard. Walks the next several ET
  calendar days and returns each game's teams + status, sorted by tip-off.
  Only WNBA has a live feed today; other sports return an empty schedule.
  """
  alias HeadsUp.Sports.Espn.Client

  @et_offset_seconds -4 * 3600
  @days 8

  @doc "Upcoming games for a sport. `opts[:client]` injects a stub in tests."
  def upcoming(sport, opts \\ []) do
    client = Keyword.get(opts, :client, Client)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    if sport == "wnba", do: {:ok, fetch(client, now)}, else: {:ok, []}
  end

  defp fetch(client, now) do
    start = now |> DateTime.add(@et_offset_seconds, :second) |> DateTime.to_date()

    0..(@days - 1)
    |> Enum.flat_map(fn d ->
      ymd = start |> Date.add(d) |> Calendar.strftime("%Y%m%d")

      case client.scoreboard(ymd) do
        {:ok, body} -> body |> Map.get("events", []) |> Enum.map(&game/1)
        {:error, _} -> []
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.date)
  end

  defp game(event) do
    comp = event |> Map.get("competitions", []) |> List.first() || %{}
    competitors = Map.get(comp, "competitors", [])
    home = Enum.find(competitors, &(&1["homeAway"] == "home"))
    away = Enum.find(competitors, &(&1["homeAway"] == "away"))

    if home && away do
      %{
        id: to_string(event["id"]),
        date: event["date"],
        state: get_in(event, ["status", "type", "state"]),
        status: get_in(event, ["status", "type", "shortDetail"]) || get_in(event, ["status", "type", "description"]),
        home: side(home),
        away: side(away)
      }
    end
  end

  defp side(competitor) do
    team = Map.get(competitor, "team", %{})

    %{
      abbrev: team["abbreviation"],
      name: team["shortDisplayName"] || team["displayName"] || team["name"],
      logo: team["logo"],
      score: competitor["score"]
    }
  end
end
