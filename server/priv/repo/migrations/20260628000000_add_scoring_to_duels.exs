defmodule HeadsUp.Repo.Migrations.AddScoringToDuels do
  use Ecto.Migration

  def change do
    alter table(:duels) do
      # Frozen scoring window (set when the draft finishes); the settlement
      # worker sweeps duels whose window has closed.
      add :scoring_window_start, :utc_datetime
      add :scoring_window_end, :utc_datetime

      # Denormalized outcome for cheap list/show rendering. winner_id nil while
      # status == "settled" means a tie. Scores + breakdown are in settlement_results.
      add :winner_id, references(:users, on_delete: :nilify_all)
      add :settled_at, :utc_datetime
    end

    # The worker's sweep predicate: status = "drafted" AND scoring_window_end <= now.
    create index(:duels, [:status, :scoring_window_end])
    create index(:duels, [:winner_id])
  end
end
