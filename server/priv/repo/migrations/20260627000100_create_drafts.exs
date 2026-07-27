defmodule HeadsUp.Repo.Migrations.CreateDrafts do
  use Ecto.Migration

  def change do
    create table(:drafts) do
      add :duel_id, references(:duels, on_delete: :delete_all), null: false
      # lobby (ready-check) | active (clock running) | complete | cancelled
      add :status, :string, null: false, default: "lobby"
      # Coin-flip winner who makes pick #1. Null until both ready -> active.
      add :first_picker_id, references(:users, on_delete: :nilify_all)
      # 1-indexed pointer to the pick currently ON THE CLOCK.
      add :current_pick_number, :integer, null: false, default: 1
      # roster_size * 2, snapshot so the draft is self-contained.
      add :total_picks, :integer, null: false
      # Wall-clock instant the current pick auto-picks; null in lobby.
      add :clock_deadline, :utc_datetime
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # One draft per duel (race-safe lazy creation relies on this).
    create unique_index(:drafts, [:duel_id])
    create index(:drafts, [:status])
  end
end
