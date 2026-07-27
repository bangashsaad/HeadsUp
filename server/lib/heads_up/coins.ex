defmodule HeadsUp.Coins do
  @moduledoc """
  The Coins context: HeadsUp's in-house virtual currency, backed by a
  double-entry ledger. Coins are free for the beta — they can't be bought,
  cashed out, or transferred between users — which is exactly what keeps
  staked duels legally inert (no consideration in, no prize of value out).

  ## Hard rules

  - Every coin movement is a balanced transaction posted here. No direct
    balance writes, anywhere.
  - `coin_txns` and `coin_entries` are append-only (DB triggers). Corrections
    are new reversing transactions.
  - Entry amounts are signed integers: debits positive, credits negative;
    every transaction sums to zero. Wallets are credit-normal — a wallet
    holding 1,000 coins has a signed sum of -1,000; `balance/1` returns the
    natural (non-negative) number humans see.
  - No wallet ever goes negative (row-locked overdraft guard).
  - Product movements carry idempotency keys (e.g. "duel:42:settle"); a
    replay returns the original transaction without moving anything.

  ## Composing with duel transitions

  The duel verbs (`stake/4`, `refund/4`, `settle/6`) take the caller's `repo`
  and run INSIDE the caller's transaction (an `Ecto.Multi.run` step), so a
  duel can never change status without its coins moving, or vice versa.
  `post/1` and `grant/4` open their own transaction.
  """

  import Ecto.Query, warn: false

  alias HeadsUp.Coins.{Account, Balance, Entry, Txn}
  alias HeadsUp.Repo

  @signup_grant 1_000
  @comeback_grant 100
  @comeback_floor 25
  @stake_max 10_000
  # The scoreboard's ET convention (Sports.Schedule) — the comeback bonus
  # resets on the US sports calendar day, not UTC.
  @et_offset_seconds -4 * 3600

  def signup_grant, do: @signup_grant
  def stake_max, do: @stake_max

  ## Reads -------------------------------------------------------------------

  @doc "The user's natural coin balance (0 if their wallet was never opened)."
  @spec balance(integer()) :: integer()
  def balance(user_id) do
    from(a in Account,
      join: b in Balance,
      on: b.account_id == a.id,
      where: a.owner_user_id == ^user_id,
      select: -b.amount
    )
    |> Repo.one() || 0
  end

  @doc """
  The user's recent wallet movements, newest first, in natural sign (coins in
  positive, coins out negative), with the transaction's kind + metadata.
  """
  def history(user_id, limit \\ 50) do
    from(e in Entry,
      join: a in Account,
      on: a.id == e.account_id,
      join: t in Txn,
      on: t.id == e.txn_id,
      where: a.owner_user_id == ^user_id,
      order_by: [desc: e.id],
      limit: ^limit,
      select: %{id: e.id, amount: -e.amount, kind: t.kind, metadata: t.metadata, inserted_at: e.inserted_at}
    )
    |> Repo.all()
  end

  @doc "Fetches a system account by its unique code. Raises if missing."
  def system_account!(code), do: Repo.get_by!(Account, code: code)

  ## Grants (the only faucet) -------------------------------------------------

  @doc "The one-time signup grant. Idempotent — safe to call again (backfill)."
  def grant_signup(user_id) do
    grant(user_id, @signup_grant, "grant:signup:#{user_id}", %{"reason" => "signup"})
  end

  @doc """
  The comeback bonus: +#{@comeback_grant} when the balance is under
  #{@comeback_floor}, at most once per ET calendar day. Called lazily from
  GET /api/me — no worker needed. The date-stamped idempotency key is the
  once-a-day guard.
  """
  def maybe_comeback(user_id) do
    if balance(user_id) < @comeback_floor do
      grant(user_id, @comeback_grant, "grant:comeback:#{user_id}:#{et_today()}", %{"reason" => "comeback"})
    else
      {:ok, :not_due}
    end
  end

  @doc "Mints `amount` coins into a user's wallet (nil key = not idempotent; dev only)."
  def grant(user_id, amount, idempotency_key, metadata \\ %{}) when amount > 0 do
    post(%{
      kind: "grant",
      idempotency_key: idempotency_key,
      metadata: metadata,
      entries: [
        %{account: {:system, "mint"}, amount: amount},
        %{account: {:user, user_id}, amount: -amount}
      ]
    })
  end

  ## Duel verbs (run inside the caller's transaction) --------------------------

  @doc "Escrows `amount` of the user's coins for a duel. No-op at amount 0."
  def stake(_repo, _user_id, _duel_id, 0), do: {:ok, :no_stake}

  def stake(repo, user_id, duel_id, amount) when amount > 0 do
    do_post(repo, %{
      kind: "stake",
      idempotency_key: "duel:#{duel_id}:stake:#{user_id}",
      metadata: %{"duel_id" => duel_id, "user_id" => user_id},
      entries: [
        %{account: {:user, user_id}, amount: amount},
        %{account: {:system, "escrow.duels"}, amount: -amount}
      ]
    })
  end

  @doc "Returns a staked amount from duel escrow to the user's wallet. No-op at 0."
  def refund(_repo, _user_id, _duel_id, 0), do: {:ok, :no_stake}

  def refund(repo, user_id, duel_id, amount) when amount > 0 do
    do_post(repo, %{
      kind: "refund",
      idempotency_key: "duel:#{duel_id}:refund:#{user_id}",
      metadata: %{"duel_id" => duel_id, "user_id" => user_id},
      entries: [
        %{account: {:system, "escrow.duels"}, amount: amount},
        %{account: {:user, user_id}, amount: -amount}
      ]
    })
  end

  @doc """
  Settles a duel's escrow in ONE balanced transaction, keyed "duel:{id}:settle".

  `stakers` is the ranked field (`[%{user_id, rank}]` — every player who staked);
  the pot is `stake × players`. A decisive winner takes the whole pot. On a tie
  the pot splits evenly across the rank-1 players (for a 1v1 tie that's exactly
  both stakes back); an indivisible remainder is burned back to the mint rather
  than minting a fairness dispute.
  """
  def settle(_repo, _duel_id, 0, _stakers, _winner_id, _tie?), do: {:ok, :no_stake}

  def settle(repo, duel_id, stake, stakers, winner_id, tie?) when stake > 0 do
    pot = stake * length(stakers)

    winners =
      if tie?,
        do: for(s <- stakers, s.rank == 1, do: s.user_id),
        else: [winner_id]

    share = div(pot, length(winners))
    remainder = pot - share * length(winners)

    entries =
      [%{account: {:system, "escrow.duels"}, amount: pot}] ++
        Enum.map(winners, &%{account: {:user, &1}, amount: -share}) ++
        if(remainder > 0, do: [%{account: {:system, "mint"}, amount: -remainder}], else: [])

    do_post(repo, %{
      kind: if(tie?, do: "refund", else: "payout"),
      idempotency_key: "duel:#{duel_id}:settle",
      metadata: %{
        "duel_id" => duel_id,
        "pot" => pot,
        "winner_ids" => winners,
        "share" => share,
        "tie" => tie?
      },
      entries: entries
    })
  end

  ## Posting -------------------------------------------------------------------

  @typedoc "A system account by code, or a user wallet (auto-opened on first use)."
  @type account_ref :: {:system, String.t()} | {:user, integer()} | Account.t()

  @doc """
  Posts a balanced transaction in its own DB transaction: insert txn → insert
  entries → update balances (rows locked in sorted account-id order).
  All-or-nothing; replaying an idempotency key returns the original.
  """
  def post(params) do
    Repo.transaction(fn ->
      case do_post(Repo, params) do
        {:ok, txn} -> txn
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # The posting pipeline against a caller-supplied repo. MUST run inside a
  # transaction (the duel verbs run as Ecto.Multi.run steps; post/1 wraps).
  defp do_post(repo, %{kind: kind, entries: entries} = params) when is_list(entries) do
    idempotency_key = Map.get(params, :idempotency_key)
    metadata = Map.get(params, :metadata, %{})

    with :ok <- validate_shape(entries),
         :ok <- validate_zero_sum(entries),
         {:ok, resolved} <- resolve_entries(repo, entries) do
      case fetch_by_key(repo, idempotency_key) do
        nil -> insert_posting(repo, kind, idempotency_key, metadata, resolved)
        %Txn{} = original -> {:ok, original}
      end
    end
  end

  defp do_post(_repo, _params), do: {:error, :invalid_posting}

  defp validate_shape(entries) when length(entries) < 2, do: {:error, :too_few_entries}

  defp validate_shape(entries) do
    if Enum.all?(entries, fn
         %{account: _ref, amount: amount} -> is_integer(amount) and amount != 0
         _ -> false
       end),
       do: :ok,
       else: {:error, :invalid_entry}
  end

  defp validate_zero_sum(entries) do
    if entries |> Enum.map(& &1.amount) |> Enum.sum() == 0, do: :ok, else: {:error, :unbalanced}
  end

  defp resolve_entries(repo, entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
      case resolve_account(repo, entry.account) do
        {:ok, %Account{} = account} -> {:cont, {:ok, [%{entry | account: account} | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      error -> error
    end
  end

  defp resolve_account(_repo, %Account{} = account), do: {:ok, account}

  defp resolve_account(repo, {:system, code}) do
    case repo.get_by(Account, code: code) do
      nil -> {:error, :unknown_account}
      account -> {:ok, account}
    end
  end

  # Wallets are auto-opened on first use, so no user can ever be missing one.
  defp resolve_account(repo, {:user, user_id}) do
    case repo.get_by(Account, owner_user_id: user_id) do
      nil -> create_wallet(repo, user_id)
      account -> {:ok, account}
    end
  end

  defp create_wallet(repo, user_id) do
    case repo.insert(Account.changeset(%Account{}, %{owner_user_id: user_id, kind: "wallet"})) do
      {:ok, account} ->
        repo.insert!(%Balance{account_id: account.id})
        {:ok, account}

      {:error, _changeset} ->
        # Lost a race with a concurrent open for the same user.
        case repo.get_by(Account, owner_user_id: user_id) do
          nil -> {:error, :wallet_creation_failed}
          account -> {:ok, account}
        end
    end
  end

  defp insert_posting(repo, kind, idempotency_key, metadata, resolved) do
    changeset =
      Txn.changeset(%Txn{}, %{kind: kind, idempotency_key: idempotency_key, metadata: metadata})

    with {:ok, txn} <- repo.insert(changeset),
         {:ok, entries} <- insert_entries(repo, txn, resolved),
         {:ok, _balances} <- apply_balances(repo, resolved) do
      {:ok, %{txn | entries: entries}}
    end
  end

  defp insert_entries(repo, txn, resolved) do
    Enum.reduce_while(resolved, {:ok, []}, fn spec, {:ok, acc} ->
      changeset =
        Entry.changeset(%Entry{}, %{txn_id: txn.id, account_id: spec.account.id, amount: spec.amount})

      case repo.insert(changeset) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  # Locks the touched balance rows FOR UPDATE in ascending account-id order
  # (prevents lock-order deadlocks), applies the deltas, and rejects any
  # wallet whose natural balance would go negative (signed sum > 0).
  defp apply_balances(repo, resolved) do
    deltas = aggregate_deltas(resolved)
    account_ids = Map.keys(deltas)

    locked =
      repo.all(
        from(b in Balance,
          where: b.account_id in ^account_ids,
          order_by: [asc: b.account_id],
          lock: "FOR UPDATE"
        )
      )

    if length(locked) == length(account_ids) do
      update_balances(repo, locked, deltas)
    else
      {:error, :missing_balance_row}
    end
  end

  defp aggregate_deltas(resolved) do
    Enum.reduce(resolved, %{}, fn %{account: account, amount: amount}, acc ->
      Map.update(acc, account.id, {amount, 1, account}, fn {sum, count, ^account} ->
        {sum + amount, count + 1, account}
      end)
    end)
  end

  defp update_balances(repo, locked, deltas) do
    computed =
      Enum.map(locked, fn balance ->
        {delta, count, account} = Map.fetch!(deltas, balance.account_id)
        %{balance: balance, delta: delta, count: count, account: account, new_amount: balance.amount + delta}
      end)

    # Guard EVERY wallet before touching ANY row, so a rejected posting writes
    # no balances at all (the caller's transaction still discards the txn row).
    overdrawn? = fn %{account: account, new_amount: new_amount} ->
      account.kind == "wallet" and new_amount > 0
    end

    if Enum.any?(computed, overdrawn?) do
      {:error, :insufficient_coins}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for %{balance: balance, delta: delta, count: count} <- computed do
        {_n, _} =
          repo.update_all(
            from(b in Balance, where: b.account_id == ^balance.account_id),
            inc: [amount: delta, entry_count: count],
            set: [updated_at: now]
          )
      end

      {:ok, Map.new(computed, fn %{balance: b, new_amount: new} -> {b.account_id, new} end)}
    end
  end

  defp fetch_by_key(_repo, nil), do: nil

  defp fetch_by_key(repo, key) do
    case repo.get_by(Txn, idempotency_key: key) do
      nil -> nil
      txn -> repo.preload(txn, :entries)
    end
  end

  defp et_today do
    DateTime.utc_now() |> DateTime.add(@et_offset_seconds, :second) |> DateTime.to_date()
  end
end
