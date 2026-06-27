defmodule HeadsUp.Repo.Migrations.AddProjectionToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      # Higher = better. Drives the draft board order and position-aware
      # auto-pick. Seeded per sport by rank; real ADP later.
      add :projection, :float, null: false, default: 0.0
    end

    create index(:players, [:sport, :projection])
  end
end
