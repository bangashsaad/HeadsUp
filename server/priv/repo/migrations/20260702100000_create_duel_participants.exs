defmodule HeadsUp.Repo.Migrations.CreateDuelParticipants do
  use Ecto.Migration

  # Seats for multiplayer contests (up to 4 players). Seat 0 is the host
  # (always accepted); invitees hold seats 1..3 and accept/decline their own
  # seat. Existing 1v1 duels are backfilled: challenger -> seat 0, opponent ->
  # seat 1 with a status derived from where the duel got to.
  def up do
    create table(:duel_participants) do
      add :duel_id, references(:duels, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :seat, :integer, null: false
      add :status, :string, null: false, default: "invited"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:duel_participants, [:duel_id, :user_id])
    create unique_index(:duel_participants, [:duel_id, :seat])
    create index(:duel_participants, [:user_id])

    execute """
    INSERT INTO duel_participants (duel_id, user_id, seat, status, inserted_at, updated_at)
    SELECT d.id, d.challenger_id, 0, 'accepted', d.inserted_at, d.updated_at FROM duels d
    UNION ALL
    SELECT d.id, d.opponent_id, 1,
      CASE d.status
        WHEN 'declined' THEN 'declined'
        WHEN 'pending' THEN 'invited'
        WHEN 'countered' THEN 'invited'
        WHEN 'cancelled' THEN 'invited'
        ELSE 'accepted'
      END,
      d.inserted_at, d.updated_at
    FROM duels d
    """
  end

  def down do
    drop table(:duel_participants)
  end
end
