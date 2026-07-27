defmodule HeadsUp.Repo.Migrations.CreateSettlementResults do
  use Ecto.Migration

  def change do
    create table(:settlement_results) do
      add :duel_id, references(:duels, on_delete: :delete_all), null: false
      add :winner_id, references(:users, on_delete: :nilify_all)
      add :is_tie, :boolean, null: false, default: false
      add :challenger_points, :float, null: false
      add :opponent_points, :float, null: false
      add :settled_at, :utc_datetime, null: false
      # Role-keyed per-player snapshot: %{"challenger" => %{total, players: [...]},
      # "opponent" => ...}. Frozen so the scoreboard is independent of the provider.
      add :breakdown, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    # 1:1 with a duel — also the DB-level double-settle guard.
    create unique_index(:settlement_results, [:duel_id])
  end
end
