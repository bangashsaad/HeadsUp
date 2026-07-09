defmodule HeadsUp.Coins.Integrity do
  @moduledoc """
  Re-derivation and zero-sum assertions for the coin ledger. `coin_balances`
  is a cache; `coin_entries` is the truth. `check/0` re-derives every balance,
  verifies every transaction sums to zero, that no wallet is negative, and —
  the HeadsUp-specific invariant — that the escrow account holds exactly the
  coins the live duels say it should.
  """

  import Ecto.Query, warn: false

  alias HeadsUp.Coins
  alias HeadsUp.Contests
  alias HeadsUp.Repo

  @type issue ::
          {:balance_mismatch, account_id :: integer()}
          | {:unbalanced_txn, txn_id :: integer()}
          | {:negative_wallet, account_id :: integer()}
          | {:escrow_mismatch, %{escrow: integer(), expected: integer()}}

  @spec check() :: :ok | {:error, [issue()]}
  def check do
    issues =
      balance_mismatches() ++ unbalanced_txns() ++ negative_wallets() ++ escrow_mismatch()

    if issues == [], do: :ok, else: {:error, issues}
  end

  defp balance_mismatches do
    %{rows: rows} =
      Repo.query!("""
      SELECT b.account_id
      FROM coin_balances b
      LEFT JOIN coin_entries e ON e.account_id = b.account_id
      GROUP BY b.account_id, b.amount, b.entry_count
      HAVING b.amount <> COALESCE(sum(e.amount), 0)
          OR b.entry_count <> count(e.id)
      """)

    for [account_id] <- rows, do: {:balance_mismatch, account_id}
  end

  defp unbalanced_txns do
    %{rows: rows} =
      Repo.query!("""
      SELECT txn_id
      FROM coin_entries
      GROUP BY txn_id
      HAVING sum(amount) <> 0
      """)

    for [txn_id] <- rows, do: {:unbalanced_txn, txn_id}
  end

  # Wallets are credit-normal: a positive signed sum means the user owes the
  # house coins, which the overdraft guard forbids.
  defp negative_wallets do
    %{rows: rows} =
      Repo.query!("""
      SELECT a.id
      FROM coin_accounts a
      JOIN coin_balances b ON b.account_id = a.id
      WHERE a.kind = 'wallet' AND b.amount > 0
      """)

    for [account_id] <- rows, do: {:negative_wallet, account_id}
  end

  # Escrow reconciliation: what the ledger holds vs. what the duels imply.
  # Catches orphaned stakes (e.g. a duel row deleted out from under its escrow).
  defp escrow_mismatch do
    escrow =
      Coins.system_account!("escrow.duels")
      |> then(fn account ->
        from(b in HeadsUp.Coins.Balance, where: b.account_id == ^account.id, select: -b.amount)
        |> Repo.one() || 0
      end)

    expected = Contests.expected_escrow_coins()

    if escrow == expected, do: [], else: [{:escrow_mismatch, %{escrow: escrow, expected: expected}}]
  end
end
