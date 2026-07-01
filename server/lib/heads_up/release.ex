defmodule HeadsUp.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :heads_up

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Seed the live player pools from ESPN (WNBA + MLB): rosters -> FPPG projections
  -> prune legacy placeholders. Network-bound (hits ESPN). Run once after the
  first deploy + migrate: `bin/heads_up eval "HeadsUp.Release.seed()"`.
  """
  def seed do
    load_app()
    {:ok, _} = Application.ensure_all_started(:req)

    for repo <- repos() do
      Ecto.Migrator.with_repo(repo, fn _repo ->
        for sport <- ["wnba", "mlb"] do
          {:ok, _} = HeadsUp.Sports.Seeds.run_from_espn(sport)
          {:ok, _} = HeadsUp.Sports.Seeds.refresh_projections(sport)
          HeadsUp.Sports.Seeds.prune_legacy(sport)
        end
      end)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
