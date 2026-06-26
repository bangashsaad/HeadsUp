defmodule HeadsUp.Repo.Migrations.CreateSports do
  use Ecto.Migration

  def change do
    # The athletes you can draft.
    create table(:players) do
      add :sport, :string, null: false
      # external_id = this player's id at the stats provider (or our seed slug).
      add :external_id, :string, null: false
      add :name, :string, null: false
      add :team, :string
      add :position, :string
      timestamps(type: :utc_datetime)
    end

    # One row per player per sport; lets us upsert on re-seed without duplicates.
    create unique_index(:players, [:sport, :external_id])
    create index(:players, [:sport])
    create index(:players, [:sport, :position])

    # Real-world games (used later for the draft pool + scoring window).
    create table(:games) do
      add :sport, :string, null: false
      add :external_id, :string, null: false
      add :home_team, :string, null: false
      add :away_team, :string, null: false
      add :starts_at, :utc_datetime
      add :status, :string, null: false, default: "scheduled"
      timestamps(type: :utc_datetime)
    end

    create unique_index(:games, [:sport, :external_id])
    create index(:games, [:sport, :starts_at])
  end
end
