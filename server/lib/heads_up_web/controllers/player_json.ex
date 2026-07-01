defmodule HeadsUpWeb.PlayerJSON do
  alias HeadsUp.Sports.Player

  def index(%{players: players, positions: positions}) do
    %{
      players: Enum.map(players, &data/1),
      positions: positions
    }
  end

  def search(%{players: players}), do: %{players: Enum.map(players, &data/1)}

  def data(%Player{} = player) do
    %{
      id: player.id,
      sport: player.sport,
      name: player.name,
      team: player.team,
      position: player.position,
      projection: player.projection
    }
  end

  def profile(%{profile: p}) do
    %{
      player: data(p.player),
      available: p.available,
      season: p.season,
      games: p.games
    }
  end
end
