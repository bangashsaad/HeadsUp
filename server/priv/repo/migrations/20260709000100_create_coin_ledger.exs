defmodule HeadsUp.Repo.Migrations.CreateCoinLedger do
  use Ecto.Migration

  @moduledoc """
  The coin ledger: double-entry accounts / transactions / entries plus a
  cached balance per account. System accounts ("mint", "escrow.duels") are
  seeded here so every environment has them before any posting runs.
  """

  def change do
    create table(:coin_accounts) do
      add :code, :string
      add :kind, :string, null: false
      # No on_delete: deleting a user with coin history must fail loudly —
      # the append-only entries can't cascade anyway.
      add :owner_user_id, references(:users)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:coin_accounts, [:code])
    create unique_index(:coin_accounts, [:owner_user_id])

    create constraint(:coin_accounts, :code_or_owner_required,
             check: "(code IS NOT NULL) <> (owner_user_id IS NOT NULL)"
           )

    create table(:coin_txns) do
      add :kind, :string, null: false
      add :idempotency_key, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:coin_txns, [:idempotency_key])

    create table(:coin_entries) do
      add :txn_id, references(:coin_txns), null: false
      add :account_id, references(:coin_accounts), null: false
      add :amount, :bigint, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:coin_entries, [:account_id])
    create index(:coin_entries, [:txn_id])
    create constraint(:coin_entries, :amount_nonzero, check: "amount <> 0")

    create table(:coin_balances, primary_key: false) do
      add :account_id, references(:coin_accounts), primary_key: true
      add :amount, :bigint, null: false, default: 0
      add :entry_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime, inserted_at: false)
    end

    execute(
      """
      INSERT INTO coin_accounts (code, kind, inserted_at, updated_at)
      VALUES ('mint', 'asset', now(), now()), ('escrow.duels', 'liability', now(), now())
      """,
      "DELETE FROM coin_accounts WHERE code IN ('mint', 'escrow.duels')"
    )

    execute(
      """
      INSERT INTO coin_balances (account_id, amount, entry_count, updated_at)
      SELECT id, 0, 0, now() FROM coin_accounts WHERE code IN ('mint', 'escrow.duels')
      """,
      ""
    )
  end
end
