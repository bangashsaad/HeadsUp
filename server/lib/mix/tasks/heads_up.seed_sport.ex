defmodule Mix.Tasks.HeadsUp.SeedSport do
  @shortdoc "Re-seed a sport's player pool from ESPN (+ FPPG projections)"
  @moduledoc """
  Re-seed any live-feed sport's player pool from ESPN, then compute season FPPG
  into `projection`. Two phases: roster upsert (transactional) + a network-bound
  FPPG pass (resilient per player).

      mix heads_up.seed_sport wnba
      mix heads_up.seed_sport mlb

  `heads_up.seed_wnba` / `heads_up.seed_mlb` are thin aliases for this.
  """
  use Mix.Task

  alias HeadsUp.Sports
  alias HeadsUp.Sports.Espn.Client

  @requirements ["app.start"]

  @impl true
  def run([sport]), do: seed(sport)
  def run(_), do: Mix.raise("usage: mix heads_up.seed_sport <#{Enum.join(Client.leagues(), "|")}>")

  @doc "Run both seed phases for `sport`, printing a summary."
  def seed(sport) do
    unless Client.supported?(sport) do
      Mix.raise("no ESPN feed for sport #{inspect(sport)} (have: #{Enum.join(Client.leagues(), ", ")})")
    end

    before = Sports.count_players()

    case Sports.Seeds.run_from_espn(sport) do
      {:ok, %{inserted: ins, updated: upd, total: total}} ->
        Mix.shell().info("#{sport} roster upsert: #{upd} matched, #{ins} new, #{total} touched.")

      {:error, reason} ->
        Mix.raise("#{sport} re-seed failed (no rows written): #{inspect(reason)}")
    end

    pruned = Sports.Seeds.prune_legacy(sport)
    if pruned > 0, do: Mix.shell().info("Pruned #{pruned} legacy placeholder players.")

    Mix.shell().info("Computing FPPG projections from game logs (network-bound)…")
    {:ok, %{updated: u, total: t}} = Sports.Seeds.refresh_projections(sport)

    Mix.shell().info("""
    #{sport} seed complete.
      FPPG set:      #{u}/#{t} players
      players total: #{before} -> #{Sports.count_players()}
    """)
  end
end
