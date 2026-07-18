defmodule HeadsUp.Repo.Migrations.AddDeletedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Account deletion = anonymize-and-scrub (PII wiped, logins dead), never
      # a hard DELETE: cascades would erase OPPONENTS' duel history and tear
      # holes in the double-entry coin ledger. This stamp marks the ghosts.
      add :deleted_at, :utc_datetime
    end
  end
end
