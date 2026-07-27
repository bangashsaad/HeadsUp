defmodule Mix.Tasks.Bout.SeedMlb do
  @shortdoc "Re-seed the MLB player pool from the live ESPN feed (+ FPPG)"
  @moduledoc """
  Pull every MLB team's roster from ESPN and upsert our player pool (real ESPN
  athlete ids, team abbreviations, SP/RP/C/1B/… positions), then compute each
  player's season FPPG into `projection`.

      mix bout.seed_mlb

  Idempotent and network-bound. Thin alias for `mix bout.seed_sport mlb`.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(_args), do: Mix.Tasks.Bout.SeedSport.seed("mlb")
end
