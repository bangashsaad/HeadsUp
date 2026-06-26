defmodule HeadsUp.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    # citext = case-insensitive text, so "Nyel" and "nyel" are treated as the
    # same username/email and can't both be registered.
    execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"

    create table(:users) do
      add :username, :citext, null: false
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:username])

    # Login tokens — the "wristband" we hand the phone so it stays logged in.
    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
