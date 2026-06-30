defmodule HeadsUp.Sports.Profile do
  @moduledoc """
  Assembles a player's profile — season averages + a fantasy game log — from the
  ESPN feed. Per-game fantasy points reuse the same `Settlement.Engine` math the
  duels settle with, so a player's profile and their duel score agree.

  Only players with a numeric ESPN `external_id` (the WNBA pool, re-seeded in
  Phase 5b) have real data; everyone else returns `available: false`.
  """
  alias HeadsUp.Sports.Espn.{Client, Parse}
  alias HeadsUp.Contests.Scoring
  alias HeadsUp.Settlement.Engine
  alias HeadsUp.Sports.Player

  @avg_keys ~w(minutes points rebounds assists steals blocks turnovers three_made fantasy)a

  @doc """
  Build the profile for a player. `opts[:client]` injects a stub in tests.
  Returns `{:ok, %{available, player, season, games}}`.
  """
  def for_player(%Player{} = player, opts \\ []) do
    client = Keyword.get(opts, :client, Client)

    if espn_id?(player.external_id) do
      {:ok, assemble(player, client)}
    else
      {:ok, %{available: false, player: player, season: nil, games: []}}
    end
  end

  defp espn_id?(eid), do: is_binary(eid) and Regex.match?(~r/^\d+$/, eid)

  defp assemble(player, client) do
    rules = Scoring.default_rules(player.sport)

    games =
      case client.gamelog(player.external_id) do
        {:ok, body} -> parse_games(body, rules)
        {:error, _} -> []
      end

    %{available: true, player: player, season: season_averages(games), games: games}
  end

  # --- game log -----------------------------------------------------------

  defp parse_games(body, rules) do
    labels = body["labels"] || []
    meta = body["events"] || %{}

    stats_by_event =
      for st <- body["seasonTypes"] || [],
          cat <- st["categories"] || [],
          e <- cat["events"] || [],
          into: %{},
          do: {to_string(e["eventId"]), e["stats"] || []}

    meta
    |> Enum.map(fn {eid, m} -> {to_string(eid), m} end)
    |> Enum.filter(fn {eid, _m} -> Map.has_key?(stats_by_event, eid) end)
    |> Enum.map(fn {eid, m} -> game(eid, m, Map.fetch!(stats_by_event, eid), labels, rules) end)
    |> Enum.sort_by(& &1.date, :desc)
  end

  defp game(eid, meta, stats, labels, rules) do
    line = %{
      "point" => count(labels, stats, "PTS"),
      "rebound" => count(labels, stats, "REB"),
      "assist" => count(labels, stats, "AST"),
      "steal" => count(labels, stats, "STL"),
      "block" => count(labels, stats, "BLK"),
      "turnover" => count(labels, stats, "TO"),
      "three_made" => made(labels, stats, "3PT")
    }

    %{
      event_id: eid,
      date: meta["gameDate"],
      opponent: get_in(meta, ["opponent", "abbreviation"]) || get_in(meta, ["opponent", "displayName"]),
      home_away: meta["atVs"],
      result: meta["gameResult"],
      minutes: count(labels, stats, "MIN"),
      points: line["point"],
      rebounds: line["rebound"],
      assists: line["assist"],
      steals: line["steal"],
      blocks: line["block"],
      turnovers: line["turnover"],
      three_made: line["three_made"],
      fg: cell(labels, stats, "FG"),
      three_pt: cell(labels, stats, "3PT"),
      ft: cell(labels, stats, "FT"),
      fantasy: Float.round(Engine.player_points(line, rules) * 1.0, 1)
    }
  end

  # --- season (computed from the game log) --------------------------------

  defp season_averages([]), do: %{games_played: 0}

  defp season_averages(games) do
    n = length(games)
    base = %{games_played: n}

    Enum.reduce(@avg_keys, base, fn key, acc ->
      total = games |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum()
      Map.put(acc, key, Float.round(total / n, 1))
    end)
  end

  # --- cell readers -------------------------------------------------------

  defp cell(labels, stats, label), do: Parse.stat_value(labels, stats, label)
  defp count(labels, stats, label), do: Parse.to_int(Parse.stat_value(labels, stats, label))
  defp made(labels, stats, label), do: Parse.made_from(Parse.stat_value(labels, stats, label))
end
