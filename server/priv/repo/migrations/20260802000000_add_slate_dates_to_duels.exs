defmodule HeadsUp.Repo.Migrations.AddSlateDatesToDuels do
  use Ecto.Migration

  # A duel can now span SEVERAL slates. `slate_dates` is the authoritative list
  # of ET calendar days it drafts from and scores against; `slate_date` stays as
  # the earliest of them so older clients and existing queries keep working.
  #
  # `slate_kind` is how the list was chosen — "day" for basketball/baseball,
  # "week" for football, where a team plays once and the natural unit is the
  # whole Thu-Mon week rather than any single night.
  def up do
    alter table(:duels) do
      add :slate_dates, {:array, :date}
      add :slate_kind, :string
    end

    # Every existing slate duel is a single day.
    execute """
    UPDATE duels
       SET slate_dates = ARRAY[slate_date],
           slate_kind  = 'day'
     WHERE slate_date IS NOT NULL
    """
  end

  def down do
    alter table(:duels) do
      remove :slate_dates
      remove :slate_kind
    end
  end
end
