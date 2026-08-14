defmodule HeadsUp.Repo.Migrations.CreateDuelMessages do
  use Ecto.Migration

  # Trash talk: a persistent text thread per duel, visible to its players.
  # Messages survive the duel — the receipt is half the fun of a rivalry —
  # and delete with it (or with the sender's account) via FK cascade.
  def change do
    create table(:duel_messages) do
      add :duel_id, references(:duels, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :body, :string, size: 280, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:duel_messages, [:duel_id, :inserted_at])
  end
end
