defmodule HeadsUp.Repo.Migrations.AddEmailVerifiedToUsers do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :email_verified_at, :utc_datetime
    end

    # Everyone who signed up before verification existed is grandfathered —
    # they're the founding beta crew, their emails have been working for weeks.
    execute "UPDATE users SET email_verified_at = NOW()"
  end

  def down do
    alter table(:users) do
      remove :email_verified_at
    end
  end
end
