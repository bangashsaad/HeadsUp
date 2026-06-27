defmodule HeadsUp.Settlement.StatsProvider do
  @moduledoc """
  Swappable stats-source contract for settlement. An implementation turns a set
  of drafted players + a frozen scoring window into per-player stat lines, keyed
  by `player.id`, whose category keys EXACTLY match the sport's
  `HeadsUp.Contests.Scoring` chart keys (so the scoring engine can dot-product
  them against the frozen chart with no translation).

  Stage 5a ships `HeadsUp.Settlement.Stats.Mock`; 5b drops in a real WNBA feed by
  config swap only (`config :heads_up, :stats_provider, ...`).
  """
  alias HeadsUp.Settlement.Window
  alias HeadsUp.Sports.Player

  @typedoc "Category key like point or passing_yards mapped to a stat total."
  @type stat_line :: %{optional(String.t()) => number()}
  @type stats_by_player :: %{optional(integer()) => stat_line()}

  @doc """
  Total each player's stats within `window`. Returns a map keyed by `player.id`.
  Every input player MUST appear; every category for the sport MUST be present
  (zeros allowed) so downstream code never has to default.
  """
  @callback fetch_stats([Player.t()], Window.t()) :: stats_by_player()

  @doc """
  Whether stats for `window` are settled (safe to declare a winner). Lets a real
  feed (5b) defer settlement until games are final. The mock always returns true.
  """
  @callback stats_final?(Window.t()) :: boolean()
end
