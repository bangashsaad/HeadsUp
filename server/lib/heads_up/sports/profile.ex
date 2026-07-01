defmodule HeadsUp.Sports.Profile do
  @moduledoc """
  Assembles a player's profile — season summary tiles + a fantasy game log — from
  the ESPN feed, via the shared `Sports.Gamelog` parser so a player's profile and
  their duel score agree to the decimal.

  The output is SPORT-NEUTRAL so one mobile screen renders any sport: `season`
  carries a `tiles` list (`%{label, value}` strings the backend formats) plus a
  headline `fantasy` (FPG), and each game carries a pre-formatted one-line `line`
  box score. Basketball shows PPG/RPG/APG; baseball shows AVG/HR/RBI for hitters
  and ERA/K/IP for pitchers.

  Only players with a numeric ESPN `external_id` in a sport with a live feed have
  real data; everyone else returns `available: false`.
  """
  alias HeadsUp.Sports.{Gamelog, Player}
  alias HeadsUp.Sports.Espn.Client

  @doc """
  Build the profile for a player. `opts[:client]` injects a stub in tests.
  Returns `{:ok, %{available, player, season, games}}`.
  """
  def for_player(%Player{} = player, opts \\ []) do
    client = Keyword.get(opts, :client, Client)

    if espn_id?(player.external_id) and Client.supported?(player.sport) do
      {:ok, assemble(player, client)}
    else
      {:ok, %{available: false, player: player, season: nil, games: []}}
    end
  end

  defp espn_id?(eid), do: is_binary(eid) and Regex.match?(~r/^\d+$/, eid)

  defp assemble(player, client) do
    games =
      case client.gamelog(player.sport, player.external_id) do
        {:ok, body} -> Gamelog.parse(player.sport, body)
        {:error, _} -> []
      end

    %{
      available: true,
      player: player,
      season: season(player.sport, games),
      games: Enum.map(games, &public_game/1)
    }
  end

  defp public_game(g) do
    %{
      event_id: g.event_id,
      date: g.date,
      opponent: g.opponent,
      home_away: g.home_away,
      result: g.result,
      fantasy: g.fantasy,
      line: g.display
    }
  end

  # --- season summary (computed from the game log) ------------------------

  defp season(_sport, []), do: %{games_played: 0, fantasy: 0.0, tiles: []}

  defp season(sport, games) do
    %{
      games_played: length(games),
      fantasy: favg(games, & &1.fantasy),
      tiles: tiles(Gamelog.family(sport), games)
    }
  end

  defp tiles(:basketball, games) do
    [
      tile("PPG", num(favg(games, &(&1.box.points * 1.0)))),
      tile("RPG", num(favg(games, &(&1.box.rebounds * 1.0)))),
      tile("APG", num(favg(games, &(&1.box.assists * 1.0)))),
      tile("FPG", num(favg(games, & &1.fantasy)))
    ]
  end

  defp tiles(:baseball, games) do
    if pitcher?(games), do: pitcher_tiles(games), else: batter_tiles(games)
  end

  defp tiles(:other, games), do: [tile("FPG", num(favg(games, & &1.fantasy)))]

  defp pitcher?(games) do
    Enum.count(games, &(&1.box.role == "P")) >= Enum.count(games, &(&1.box.role != "P"))
  end

  defp pitcher_tiles(games) do
    outs = sum(games, & &1.box.outs)
    innings = outs / 3
    er = sum(games, & &1.box.er)
    k = sum(games, & &1.box.k)
    era = if innings > 0, do: 9 * er / innings, else: 0.0

    [
      tile("ERA", :erlang.float_to_binary(era * 1.0, decimals: 2)),
      tile("K", Integer.to_string(k)),
      tile("IP", ip_string(outs)),
      tile("FPG", num(favg(games, & &1.fantasy)))
    ]
  end

  defp batter_tiles(games) do
    ab = sum(games, & &1.box.ab)
    h = sum(games, & &1.box.h)
    avg = if ab > 0, do: h / ab, else: 0.0

    [
      tile("AVG", avg_string(avg)),
      tile("HR", Integer.to_string(sum(games, & &1.box.hr))),
      tile("RBI", Integer.to_string(sum(games, & &1.box.rbi))),
      tile("FPG", num(favg(games, & &1.fantasy)))
    ]
  end

  # --- formatting helpers -------------------------------------------------

  defp tile(label, value), do: %{label: label, value: value}

  defp favg([], _f), do: 0.0
  defp favg(games, f), do: Float.round(Enum.sum(Enum.map(games, f)) / length(games), 1)

  defp sum(games, f), do: games |> Enum.map(f) |> Enum.sum()

  defp num(f), do: :erlang.float_to_binary(f * 1.0, decimals: 1)

  # Batting average as ".312" (drop the leading zero, baseball convention).
  defp avg_string(avg) do
    :erlang.float_to_binary(avg * 1.0, decimals: 3) |> String.replace_prefix("0", "")
  end

  # Outs back to baseball innings notation: 122 outs -> "40.2".
  defp ip_string(outs), do: "#{div(outs, 3)}.#{rem(outs, 3)}"
end
