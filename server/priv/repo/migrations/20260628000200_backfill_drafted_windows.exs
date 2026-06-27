defmodule HeadsUp.Repo.Migrations.BackfillDraftedWindows do
  use Ecto.Migration

  # Duels already "drafted" before the scoring-window columns existed have NULL
  # windows and would never be picked up by the settlement worker. Backfill a
  # window that closes now so they settle on the next sweep.
  def up do
    execute("""
    UPDATE duels
       SET scoring_window_start = COALESCE(scoring_window_start, NOW()),
           scoring_window_end   = COALESCE(scoring_window_end, NOW())
     WHERE status = 'drafted' AND scoring_window_end IS NULL
    """)
  end

  def down, do: :ok
end
