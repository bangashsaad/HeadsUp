defmodule HeadsUp.Repo.Migrations.AddDraftTermsToDuels do
  use Ecto.Migration

  def change do
    alter table(:duels) do
      # Per-pick clock (seconds). Live presets 30/60/90; async 14400/43200/86400.
      add :pick_clock_seconds, :integer, null: false, default: 60
      # Preset key resolved to a positional lineup by HeadsUp.Drafts.Lineup.
      add :lineup_template, :string, null: false, default: "nba_standard"
    end
  end
end
