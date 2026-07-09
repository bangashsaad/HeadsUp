defmodule HeadsUp.CoinsTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.{Accounts, Coins, Repo}
  alias HeadsUp.Coins.{Account, Balance}

  describe "grants" do
    test "signup grant mints the welcome balance, idempotently" do
      u = user("g1")

      assert {:ok, _} = Coins.grant_signup(u.id)
      assert Coins.balance(u.id) == 1_000

      # A replay (backfill racing a real signup) moves nothing.
      assert {:ok, _} = Coins.grant_signup(u.id)
      assert Coins.balance(u.id) == 1_000
    end

    test "comeback bonus tops up a busted wallet, once per day" do
      u = user("g2")
      assert Coins.balance(u.id) == 0

      assert {:ok, _} = Coins.maybe_comeback(u.id)
      assert Coins.balance(u.id) == 100

      # Same day: the date-stamped key replays, nothing moves.
      assert {:ok, _} = Coins.maybe_comeback(u.id)
      assert Coins.balance(u.id) == 100
    end

    test "comeback bonus is not due above the floor" do
      u = user("g3")
      {:ok, _} = Coins.grant_signup(u.id)

      assert {:ok, :not_due} = Coins.maybe_comeback(u.id)
      assert Coins.balance(u.id) == 1_000
    end
  end

  describe "post/1 validation" do
    test "rejects an unbalanced transaction" do
      u = user("v1")

      assert {:error, :unbalanced} =
               Coins.post(%{
                 kind: "grant",
                 entries: [
                   %{account: {:system, "mint"}, amount: 100},
                   %{account: {:user, u.id}, amount: -99}
                 ]
               })
    end

    test "rejects fewer than two entries and zero amounts" do
      u = user("v2")

      assert {:error, :too_few_entries} =
               Coins.post(%{kind: "grant", entries: [%{account: {:user, u.id}, amount: 5}]})

      assert {:error, :invalid_entry} =
               Coins.post(%{
                 kind: "grant",
                 entries: [%{account: {:user, u.id}, amount: 0}, %{account: {:system, "mint"}, amount: 0}]
               })
    end

    test "rejects an unknown system account" do
      u = user("v3")

      assert {:error, :unknown_account} =
               Coins.post(%{
                 kind: "grant",
                 entries: [
                   %{account: {:system, "no.such.account"}, amount: 10},
                   %{account: {:user, u.id}, amount: -10}
                 ]
               })
    end
  end

  describe "stake / refund / settle" do
    test "staking escrows coins; overdrafts are rejected" do
      u = user("s1")
      {:ok, _} = Coins.grant_signup(u.id)

      assert {:ok, _} = Coins.stake(Repo, u.id, 9_001, 400)
      assert Coins.balance(u.id) == 600
      assert escrow_balance() == 400

      # As every real call site does, a failed posting's transaction rolls back.
      assert {:error, :insufficient_coins} = staking_transaction(u.id, 9_002, 601)
      assert Coins.balance(u.id) == 600
      assert escrow_balance() == 400

      # Clean the escrow back out so the books close balanced.
      assert {:ok, _} = Coins.refund(Repo, u.id, 9_001, 400)
      assert Coins.balance(u.id) == 1_000
      assert escrow_balance() == 0
    end

    test "stake and refund replay idempotently (same duel key moves once)" do
      u = user("s2")
      {:ok, _} = Coins.grant_signup(u.id)

      assert {:ok, _} = Coins.stake(Repo, u.id, 9_010, 250)
      assert {:ok, _} = Coins.stake(Repo, u.id, 9_010, 250)
      assert Coins.balance(u.id) == 750

      assert {:ok, _} = Coins.refund(Repo, u.id, 9_010, 250)
      assert {:ok, _} = Coins.refund(Repo, u.id, 9_010, 250)
      assert Coins.balance(u.id) == 1_000
    end

    test "a decisive settle pays the whole pot to the winner" do
      [w, l] = [user("s3w"), user("s3l")]
      for u <- [w, l], do: {:ok, _} = Coins.grant_signup(u.id)
      {:ok, _} = Coins.stake(Repo, w.id, 9_020, 250)
      {:ok, _} = Coins.stake(Repo, l.id, 9_020, 250)

      stakers = [%{user_id: w.id, rank: 1}, %{user_id: l.id, rank: 2}]
      assert {:ok, _} = Coins.settle(Repo, 9_020, 250, stakers, w.id, false)

      assert Coins.balance(w.id) == 1_250
      assert Coins.balance(l.id) == 750
      assert escrow_balance() == 0

      # Double settle replays — nobody gets paid twice.
      assert {:ok, _} = Coins.settle(Repo, 9_020, 250, stakers, w.id, false)
      assert Coins.balance(w.id) == 1_250
    end

    test "a tie splits the pot across the shared top; the remainder burns" do
      [a, b, c] = [user("s4a"), user("s4b"), user("s4c")]
      for u <- [a, b, c], do: {:ok, _} = Coins.grant_signup(u.id)
      for u <- [a, b, c], do: {:ok, _} = Coins.stake(Repo, u.id, 9_030, 25)

      # a and b share rank 1: pot 75 → 37 each, 1 coin burned to the mint.
      stakers = [%{user_id: a.id, rank: 1}, %{user_id: b.id, rank: 1}, %{user_id: c.id, rank: 3}]
      assert {:ok, _} = Coins.settle(Repo, 9_030, 25, stakers, nil, true)

      assert Coins.balance(a.id) == 1_012
      assert Coins.balance(b.id) == 1_012
      assert Coins.balance(c.id) == 975
      assert escrow_balance() == 0
    end
  end

  describe "history/2" do
    test "returns the wallet's movements in natural sign, newest first" do
      u = user("h1")
      {:ok, _} = Coins.grant_signup(u.id)
      {:ok, _} = Coins.stake(Repo, u.id, 9_040, 300)
      {:ok, _} = Coins.refund(Repo, u.id, 9_040, 300)

      assert [refund, stake, grant] = Coins.history(u.id)
      assert refund.kind == "refund" and refund.amount == 300
      assert stake.kind == "stake" and stake.amount == -300
      assert grant.kind == "grant" and grant.amount == 1_000
      assert refund.metadata["duel_id"] == 9_040
    end
  end

  # --- helpers ---------------------------------------------------------------

  # The duel verbs run as Ecto.Multi.run steps in production — an {:error, _}
  # always aborts the surrounding transaction. This mirrors that contract.
  defp staking_transaction(user_id, duel_id, amount) do
    Repo.transaction(fn ->
      case Coins.stake(Repo, user_id, duel_id, amount) do
        {:ok, txn} -> txn
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp escrow_balance do
    account = Repo.get_by!(Account, code: "escrow.duels")
    %Balance{amount: signed} = Repo.get!(Balance, account.id)
    -signed
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{
        "username" => "coin#{name}",
        "email" => "coin-#{name}@example.com",
        "password" => "password123"
      })

    u
  end
end
