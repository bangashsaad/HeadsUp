defmodule HeadsUp.Repo.Migrations.CoinLedgerGuards do
  use Ecto.Migration

  @moduledoc """
  The database itself rejects UPDATE/DELETE on the append-only coin ledger
  tables, and a deferred constraint trigger re-checks per-transaction
  zero-sum at COMMIT. Corrections are new reversing transactions.
  """

  def up do
    execute """
    CREATE FUNCTION coin_ledger_append_only() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION '% is append-only: corrections are new reversing transactions', TG_TABLE_NAME;
    END
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER coin_entries_append_only
    BEFORE UPDATE OR DELETE ON coin_entries
    FOR EACH ROW EXECUTE FUNCTION coin_ledger_append_only()
    """

    execute """
    CREATE TRIGGER coin_txns_append_only
    BEFORE UPDATE OR DELETE ON coin_txns
    FOR EACH ROW EXECUTE FUNCTION coin_ledger_append_only()
    """

    execute """
    CREATE FUNCTION coin_zero_sum_check() RETURNS trigger AS $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM coin_entries
        WHERE txn_id = NEW.txn_id
        GROUP BY txn_id
        HAVING sum(amount) <> 0
      ) THEN
        RAISE EXCEPTION 'coin transaction % does not sum to zero', NEW.txn_id;
      END IF;
      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE CONSTRAINT TRIGGER coin_entries_zero_sum
    AFTER INSERT ON coin_entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION coin_zero_sum_check()
    """
  end

  def down do
    execute "DROP TRIGGER coin_entries_zero_sum ON coin_entries"
    execute "DROP FUNCTION coin_zero_sum_check()"
    execute "DROP TRIGGER coin_txns_append_only ON coin_txns"
    execute "DROP TRIGGER coin_entries_append_only ON coin_entries"
    execute "DROP FUNCTION coin_ledger_append_only()"
  end
end
