defmodule HeadsUp.Repo.Migrations.CreateDuels do
  use Ecto.Migration

  def change do
    create table(:duels) do
      add :challenger_id, references(:users, on_delete: :delete_all), null: false
      add :opponent_id, references(:users, on_delete: :delete_all), null: false

      add :sport, :string, null: false
      add :draft_type, :string, null: false, default: "snake"
      add :roster_size, :integer, null: false
      # scoring_rules = the agreed point values (jsonb), defaulted per sport.
      add :scoring_rules, :map, null: false, default: %{}
      add :wager_cents, :integer, null: false, default: 0
      add :draft_starts_at, :utc_datetime, null: false
      add :status, :string, null: false, default: "pending"
      # If this duel is a counter-offer, points back at the offer it replaces.
      add :parent_duel_id, references(:duels, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:duels, [:challenger_id])
    create index(:duels, [:opponent_id])
    create index(:duels, [:status])
    create constraint(:duels, :challenger_not_opponent, check: "challenger_id <> opponent_id")
  end
end
