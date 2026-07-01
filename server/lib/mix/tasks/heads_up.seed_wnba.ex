defmodule Mix.Tasks.HeadsUp.SeedWnba do
  @shortdoc "Re-seed the WNBA player pool from the live ESPN feed (+ FPPG)"
  @moduledoc """
  Pull every WNBA team's roster from ESPN and upsert our player pool so each
  player's `external_id` is the ESPN athlete id the stats provider joins on, then
  compute each player's season FPPG (fantasy points/game) into `projection`.

      mix heads_up.seed_wnba

  Idempotent and network-bound (hits site.api.espn.com). Existing rows keep their
  id; the FPPG pass refreshes projection from real game logs.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(_args), do: Mix.Tasks.HeadsUp.SeedSport.seed("wnba")
end
