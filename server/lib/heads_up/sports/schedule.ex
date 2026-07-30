defmodule HeadsUp.Sports.Schedule do
  @moduledoc """
  Upcoming games from the live ESPN scoreboard. Walks the next several ET
  calendar days and returns each game's teams + status, sorted by tip-off.
  Any sport the ESPN `Client` has a league mapping for (WNBA, MLB, …) gets a
  live schedule; anything else returns an empty list.
  """
  alias HeadsUp.Sports.Espn.Client

  @et_offset_seconds -4 * 3600
  @days 8

  @doc "Upcoming games for a sport. `opts[:client]` injects a stub in tests."
  def upcoming(sport, opts \\ []) do
    client = Keyword.get(opts, :client, Client)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    if Client.supported?(sport), do: {:ok, fetch(sport, client, now)}, else: {:ok, []}
  end

  @doc "All games on one ET calendar date — past days welcome (the receipts)."
  def on_date(sport, %Date{} = date, opts \\ []) do
    client = Keyword.get(opts, :client, Client)

    if Client.supported?(sport) do
      ymd = Calendar.strftime(date, "%Y%m%d")

      games =
        case client.scoreboard(sport, ymd) do
          {:ok, body} -> body |> Map.get("events", []) |> Enum.map(&game/1)
          {:error, _} -> []
        end
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.date)

      {:ok, games}
    else
      {:ok, []}
    end
  end

  defp fetch(sport, client, now) do
    start = now |> DateTime.add(@et_offset_seconds, :second) |> DateTime.to_date()

    0..(@days - 1)
    |> Enum.flat_map(fn d ->
      ymd = start |> Date.add(d) |> Calendar.strftime("%Y%m%d")

      case client.scoreboard(sport, ymd) do
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
      # ESPN's primary team color as bare hex ("78BE20") — the mobile scoreboard
      # tints cards/glows with it.
      color: team["color"],
      score: competitor["score"],
      # Matchup preview: the season record, plus whichever pre-game story the
      # sport actually turns on. Baseball lives and dies by the probable
      # starter; basketball has no such lever, so it gets team leaders.
      record: record_summary(competitor),
      probable: probable(competitor),
      leaders: leaders(competitor)
    }
  end

  # MLB's probable starting pitcher — the single most useful pre-game fact in
  # baseball, and the reason a "list of players" reads as useless there.
  defp probable(competitor) do
    with [p | _] <- List.wrap(competitor["probables"]),
         athlete when is_map(athlete) <- p["athlete"] do
      stats = Map.new(List.wrap(p["statistics"]), &{&1["abbreviation"], &1["displayValue"]})

      %{
        id: to_string(athlete["id"] || ""),
        name: athlete["displayName"] || athlete["fullName"],
        short_name: athlete["shortName"],
        # ESPN sends position as a nested object in most feeds but as a bare
        # string on probables — handle both rather than crashing the schedule.
        position: position_abbrev(athlete["position"]),
        jersey: athlete["jersey"],
        headshot_url: athlete["headshot"],
        # "7-8 · 3.72 ERA" is the whole story at a glance.
        line: pitcher_line(stats)
      }
    else
      _ -> nil
    end
  end

  defp record_summary(competitor) do
    case List.wrap(competitor["records"]) do
      [%{"summary" => summary} | _] -> summary
      _ -> nil
    end
  end

  defp position_abbrev(%{"abbreviation" => abbrev}), do: abbrev
  defp position_abbrev(pos) when is_binary(pos), do: pos
  defp position_abbrev(_), do: nil

  defp pitcher_line(stats) do
    wl =
      case {stats["W"], stats["L"]} do
        {w, l} when is_binary(w) and is_binary(l) -> "#{w}-#{l}"
        _ -> nil
      end

    era = if stats["ERA"], do: "#{stats["ERA"]} ERA"

    [wl, era] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
  end

  # Basketball's equivalent: who leads this team in points / boards / assists.
  defp leaders(competitor) do
    competitor
    |> Map.get("leaders")
    |> List.wrap()
    # RAT is ESPN's blended "rating" line — too long for a preview row.
    |> Enum.reject(&(&1["abbreviation"] in [nil, "RAT"]))
    |> Enum.flat_map(fn cat ->
      case List.wrap(cat["leaders"]) do
        [top | _] ->
          [
            %{
              category: cat["abbreviation"],
              name: get_in(top, ["athlete", "shortName"]) || get_in(top, ["athlete", "displayName"]),
              value: top["displayValue"],
              headshot_url: get_in(top, ["athlete", "headshot"])
            }
          ]

        _ ->
          []
      end
    end)
    |> Enum.take(3)
  end
end
