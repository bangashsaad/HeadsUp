defmodule HeadsUp.Sports do
  @moduledoc """
  The Sports context: the players you can draft and the games they play in.
  """

  import Ecto.Query, warn: false
  alias HeadsUp.Repo
  alias HeadsUp.Sports.{Player, Game}

  @sports ~w(nfl nba mlb wnba)

  def sports, do: @sports

  @doc """
  Lists players for a sport. Options: `:q` (name contains), `:position`, `:limit`.
  """
  def list_players(sport, opts \\ []) when is_binary(sport) do
    Player
    |> where([p], p.sport == ^sport)
    |> filter_position(Keyword.get(opts, :position))
    |> filter_team(Keyword.get(opts, :team))
    |> filter_name(Keyword.get(opts, :q))
    |> order_by([p], desc: p.projection, asc: p.name)
    |> limit(^Keyword.get(opts, :limit, 200))
    |> Repo.all()
  end

  def get_player(id), do: Repo.get(Player, id)

  @doc """
  Cross-sport player search by name. Only returns real ESPN-seeded players
  (numeric external_id) so results are all profile-able, ranked by projection.
  """
  def search_players(q, opts \\ []) when is_binary(q) do
    Player
    |> where([p], fragment("? ~ '^[0-9]+$'", p.external_id))
    |> filter_name(q)
    |> order_by([p], desc: p.projection, asc: p.name)
    |> limit(^Keyword.get(opts, :limit, 30))
    |> Repo.all()
  end

  @doc "Distinct positions present for a sport (sorted; for filter chips)."
  def list_positions(sport) do
    Player
    |> where([p], p.sport == ^sport and not is_nil(p.position))
    |> select([p], p.position)
    |> distinct(true)
    |> order_by([p], asc: p.position)
    |> Repo.all()
  end

  def list_games(sport) do
    Game
    |> where([g], g.sport == ^sport)
    |> order_by([g], asc: g.starts_at)
    |> Repo.all()
  end

  def count_players, do: Repo.aggregate(Player, :count)

  # --- query helpers ---

  defp filter_position(query, nil), do: query
  defp filter_position(query, ""), do: query
  defp filter_position(query, position), do: where(query, [p], p.position == ^position)

  defp filter_team(query, nil), do: query
  defp filter_team(query, ""), do: query
  defp filter_team(query, team), do: where(query, [p], p.team == ^team)

  defp filter_name(query, nil), do: query

  defp filter_name(query, q) do
    trimmed = String.trim(q)

    if trimmed == "" do
      query
    else
      pattern = "%" <> escape_like(trimmed) <> "%"
      where(query, [p], ilike(p.name, ^pattern))
    end
  end

  defp escape_like(string) do
    string
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
