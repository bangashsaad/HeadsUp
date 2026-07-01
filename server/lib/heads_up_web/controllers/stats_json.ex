defmodule HeadsUpWeb.StatsJSON do
  alias HeadsUpWeb.PublicUserJSON

  def me(%{record: record, head_to_head: h2h}) do
    %{
      record: record_data(record),
      head_to_head:
        Enum.map(h2h, fn r -> record_data(r) |> Map.put(:opponent, PublicUserJSON.public(r.opponent)) end)
    }
  end

  def leaderboard(%{rows: rows}) do
    %{
      leaderboard:
        Enum.map(rows, fn r ->
          record_data(r) |> Map.merge(%{rank: r.rank, user: PublicUserJSON.public(r.user)})
        end)
    }
  end

  defp record_data(r) do
    %{
      wins: r.wins,
      losses: r.losses,
      ties: r.ties,
      played: r.played,
      win_pct: r.win_pct,
      points_for: r.points_for,
      points_against: r.points_against,
      streak: r.streak,
      recent: r.recent
    }
  end
end
