defmodule HeadsUp.Wave4HygieneTest do
  @moduledoc "The small-batch hygiene rules: draft window, ledger health, the weekly refresh clock."
  use HeadsUp.DataCase, async: false

  alias HeadsUp.{Accounts, Coins, Contests, Health, Repo}
  alias HeadsUp.Coins.Integrity
  alias HeadsUp.Social.Friendship
  alias HeadsUp.Sports.PoolRefresher

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  setup do
    on_exit(fn -> :persistent_term.erase({Integrity, :last}) end)
    :ok
  end

  test "a challenge can't be scheduled more than 30 days out" do
    a = user("w4a")
    b = user("w4b")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
    far = DateTime.utc_now() |> DateTime.add(40 * 86_400, :second) |> DateTime.to_iso8601()
    near = DateTime.utc_now() |> DateTime.add(3 * 86_400, :second) |> DateTime.to_iso8601()

    assert {:error, %Ecto.Changeset{} = cs} =
             Contests.create_challenge(a, %{"opponent_id" => b.id, "sport" => "wnba", "draft_starts_at" => far})

    assert {"can't be more than 30 days out", _} = cs.errors[:draft_starts_at]

    assert {:ok, _} =
             Contests.create_challenge(a, %{"opponent_id" => b.id, "sport" => "wnba", "draft_starts_at" => near})
  end

  test "the ledger check feeds /api/health: clean is green, a corrupted balance is a 503" do
    u = user("w4ledger")
    {:ok, _} = Coins.grant_signup(u.id)

    assert :ok = Integrity.run()
    assert %{ok: true} = Health.report().checks.ledger

    # Corrupt the cache (the entries are the truth; the balance must re-derive).
    Repo.update_all(Coins.Balance, set: [amount: -777])

    assert {:error, issues} = Integrity.run()
    assert Enum.any?(issues, &match?({:balance_mismatch, _}, &1))
    assert %{ok: false} = Health.report().checks.ledger
    assert Health.report().status == :degraded
  end

  test "the weekly refresh fires Wednesdays after 6am ET, once" do
    wed_noon_et = ~U[2026-08-26 16:00:00Z]
    wed_5am_et = ~U[2026-08-26 09:00:00Z]
    tue = ~U[2026-08-25 16:00:00Z]

    assert PoolRefresher.due?("nfl", nil, wed_noon_et)
    refute PoolRefresher.due?("nfl", nil, wed_5am_et)
    refute PoolRefresher.due?("nfl", nil, tue)
    refute PoolRefresher.due?("nfl", ~D[2026-08-26], wed_noon_et)
    assert PoolRefresher.due?("nfl", ~D[2026-08-19], wed_noon_et)
  end
end
