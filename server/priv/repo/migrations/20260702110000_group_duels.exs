defmodule HeadsUp.Repo.Migrations.GroupDuels do
  use Ecto.Migration

  # Group duels (3-4 players) have no single opponent: opponent_id goes NULL
  # and duel_participants carries the seats. 1v1 duels keep both columns set.
  #
  # drafts.pick_order persists the randomized N-player base order (round 1 of
  # the snake) so a crashed draft can rebuild the exact sequence on replay —
  # first_picker_id alone can't reconstruct a >2-player permutation.
  def up do
    execute "ALTER TABLE duels ALTER COLUMN opponent_id DROP NOT NULL"

    alter table(:drafts) do
      add :pick_order, {:array, :integer}
    end
  end

  def down do
    alter table(:drafts) do
      remove :pick_order
    end

    execute "ALTER TABLE duels ALTER COLUMN opponent_id SET NOT NULL"
  end
end
