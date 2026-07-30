defmodule HeadsUp.Sports.Headshot do
  @moduledoc """
  Player photo URLs. Our `players.external_id` IS the ESPN athlete id for any
  pool seeded from the live feed, so a headshot is already addressable — no
  extra column, no scraping, nothing to keep in sync.

  Everything routes through ESPN's image resizer rather than the raw file:
  a full-size headshot is ~310 KB, the resized one ~37 KB. On a draft board
  scrolling a hundred players that difference is the whole experience.

  Returns `nil` for placeholder pools (NBA/NFL rows whose external_id isn't a
  numeric ESPN id) so the client can fall back to initials.
  """

  # ESPN's headshot path segment per sport. NBA/NFL are listed so they light up
  # for free the moment those pools are seeded from the real feed.
  @paths %{
    "wnba" => "wnba",
    "nba" => "nba",
    "mlb" => "mlb",
    "nfl" => "nfl"
  }

  @doc """
  Resized headshot URL for a sport + ESPN athlete id, or nil when we can't
  build one. `width` drives the resizer; height follows ESPN's 1.37 ratio.
  """
  @spec url(String.t() | nil, String.t() | nil, keyword()) :: String.t() | nil
  def url(sport, external_id, opts \\ [])

  def url(sport, external_id, opts) when is_binary(sport) and is_binary(external_id) do
    with path when is_binary(path) <- Map.get(@paths, sport),
         true <- espn_id?(external_id) do
      w = Keyword.get(opts, :width, 200)
      h = round(w * 0.73)

      "https://a.espncdn.com/combiner/i?img=/i/headshots/#{path}/players/full/#{external_id}.png" <>
        "&w=#{w}&h=#{h}&scale=crop&cquality=80"
    else
      _ -> nil
    end
  end

  def url(_sport, _external_id, _opts), do: nil

  @doc "Convenience for a `%Player{}` struct."
  def for_player(%{sport: sport, external_id: external_id}, opts \\ []),
    do: url(sport, external_id, opts)

  # Seeded-from-ESPN rows have numeric ids; hand-seeded placeholders look like
  # "test-wnba-1" or "nfl-qb-3" and have no photo to fetch.
  defp espn_id?(id), do: Regex.match?(~r/^[0-9]+$/, id)
end
