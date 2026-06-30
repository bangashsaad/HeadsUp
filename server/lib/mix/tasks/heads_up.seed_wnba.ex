defmodule Mix.Tasks.HeadsUp.SeedWnba do
  @shortdoc "Re-seed the WNBA player pool from the live ESPN feed"
  @moduledoc """
  Pull every WNBA team's roster from ESPN and upsert our player pool so each
  player's `external_id` is the ESPN athlete id the stats provider joins on.

      mix heads_up.seed_wnba

  Idempotent and network-bound (hits site.api.espn.com). Existing rows keep
  their id + projection; new players are inserted at the default projection.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(_args) do
    before = HeadsUp.Sports.count_players()

    case HeadsUp.Sports.Seeds.run_wnba_from_espn() do
      {:ok, %{inserted: ins, updated: upd, total: total}} ->
        after_count = HeadsUp.Sports.count_players()

        Mix.shell().info("""
        WNBA re-seed from ESPN complete.
          matched/updated: #{upd}
          inserted (new):  #{ins}
          rows touched:    #{total}
          players total:   #{before} -> #{after_count}
        """)

      {:error, reason} ->
        Mix.raise("WNBA re-seed failed (no rows written): #{inspect(reason)}")
    end
  end
end
