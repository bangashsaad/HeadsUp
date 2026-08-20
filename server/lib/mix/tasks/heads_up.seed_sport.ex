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
  def run([sport, "--prune"]), do: seed(sport, prune: true)
  def run(_), do: Mix.raise("usage: mix heads_up.seed_sport <#{Enum.join(Client.leagues(), "|")}> [--prune]")

  @doc """
  Run both seed phases for `sport`, printing a summary. `prune: true` also
  retires players the feed no longer lists (run it after roster cut-downs).
  """
  def seed(sport, opts \\ []) do
    unless Client.supported?(sport) do
      Mix.raise("no ESPN feed for sport #{inspect(sport)} (have: #{Enum.join(Client.leagues(), ", ")})")
    end

    before = Sports.count_players()

    case Sports.Seeds.run_from_espn(sport, prune: Keyword.get(opts, :prune, false)) do
      {:ok, %{inserted: ins, updated: upd, total: total} = summary} ->
        Mix.shell().info("#{sport} roster upsert: #{upd} matched, #{ins} new, #{total} touched.")

        case summary do
          %{deleted: d, retired: r} -> Mix.shell().info("Pruned: #{d} deleted, #{r} retired to FA (kept for history).")
          %{prune_skipped: why} -> Mix.shell().error("Prune SKIPPED — feed looked wrong: #{inspect(why)}")
          _ -> :ok
        end

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
