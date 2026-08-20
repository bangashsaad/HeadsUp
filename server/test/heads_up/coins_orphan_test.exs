defmodule HeadsUp.CoinsOrphanTest do
  @moduledoc "Escrow whose duel was deleted by hand can be reclaimed, and only that."
  use HeadsUp.DataCase, async: false

  import Ecto.Query

  alias HeadsUp.{Accounts, Coins, Contests, Repo}
  alias HeadsUp.Coins.Integrity
  alias HeadsUp.Contests.{Duel, Participant}
  alias HeadsUp.Social.Friendship

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    {:ok, _} = Coins.grant_signup(u.id)
    u
  end

  test "a deleted staked duel strands escrow; reclaim returns it to the mint and the ledger balances" do
    a = user("orpha")
    b = user("orphb")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
    future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()

    {:ok, live} =
      Contests.create_challenge(a, %{"opponent_id" => b.id, "sport" => "wnba", "stake_coins" => 25, "draft_starts_at" => future})

    {:ok, doomed} =
      Contests.create_challenge(a, %{"opponent_id" => b.id, "sport" => "wnba", "stake_coins" => 25, "draft_starts_at" => future})

    {:ok, _} = Contests.accept_challenge(b, doomed.id)
    assert :ok = Integrity.check()
    assert Coins.orphaned_escrow() == []

    # The manual cleanup that happened in prod: the row goes, the ledger stays.
    Repo.delete_all(from(p in Participant, where: p.duel_id == ^doomed.id))
    Repo.delete_all(from(d in Duel, where: d.id == ^doomed.id))

    assert {:error, [escrow_mismatch: %{escrow: _, expected: _}]} = Integrity.check()
    assert Coins.orphaned_escrow() == [{doomed.id, 50}]

    assert {:ok, [{doomed_id, 50}]} = Coins.reclaim_orphaned_escrow()
    assert doomed_id == doomed.id
    assert :ok = Integrity.check()
    # Idempotent, and the live duel's escrow is untouched.
    assert {:ok, []} = Coins.reclaim_orphaned_escrow()
    assert Repo.get(Duel, live.id).stake_coins == 25
  end
end
