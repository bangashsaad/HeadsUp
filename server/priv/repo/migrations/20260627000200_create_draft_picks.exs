defmodule HeadsUp.Repo.Migrations.CreateDraftPicks do
  use Ecto.Migration

  def change do
    create table(:draft_picks) do
      add :draft_id, references(:drafts, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # :restrict so a seeded player can't be deleted out from under a pick.
      add :player_id, references(:players, on_delete: :restrict), null: false
      add :pick_number, :integer, null: false
      # Assigned lineup slot key (e.g. "FLEX1", "PG1", "UTIL1").
      add :slot, :string, null: false
      add :auto_picked, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:draft_picks, [:draft_id, :pick_number])
    # Shared board: a player can be drafted at most once per draft.
    create unique_index(:draft_picks, [:draft_id, :player_id])
    create index(:draft_picks, [:draft_id, :user_id])
  end
end
