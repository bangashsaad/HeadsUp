defmodule HeadsUp.CoinsDuelsTest.StubStats do
  @moduledoc false
  @behaviour HeadsUp.Settlement.StatsProvider
  alias HeadsUp.Settlement.Window

  @impl true
  def stats_final?(%Window{}), do: true

  # Deterministic: "Star ..." scores 50, everyone else 0.
  @impl true
  def fetch_stats(players, %Window{}) do
    Map.new(players, fn p ->
      {p.id, %{"point" => if(String.starts_with?(p.name, "Star"), do: 50, else: 0)}}
    end)
  end
end

defmodule HeadsUp.CoinsDuelsTest do
  @moduledoc """
  The coin catalogue, row by row: every duel action that moves coins
  (docs/coin-system-spec.md §B), plus the escrow-reconciliation invariant.
  """
  # async: false — the settle tests swap the global stats provider.
  use HeadsUp.DataCase, async: false

  alias HeadsUp.{Accounts, Coins, Contests, Drafts, Repo, Settlement}
  alias HeadsUp.Coins.Integrity
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Drafts.Pick
  alias HeadsUp.Social.Friendship
  alias HeadsUp.Sports.Player

  setup do
    Application.put_env(:heads_up, :stats_provider, HeadsUp.CoinsDuelsTest.StubStats)
    on_exit(fn -> Application.put_env(:heads_up, :stats_provider, HeadsUp.Settlement.Stats.Mock) end)

    a = user("a")
    b = user("b")
    befriend(a, b)
    for u <- [a, b], do: {:ok, _} = Coins.grant_signup(u.id)
    %{a: a, b: b}
  end

  describe "create (B1)" do
    test "the challenger's stake is escrowed with the duel", %{a: a, b: b} do
      duel = challenge(a, b, %{"stake_coins" => 250})

      assert duel.stake_coins == 250
      assert Coins.balance(a.id) == 750
      assert Coins.balance(b.id) == 1_000
      assert Contests.expected_escrow_coins() == 250
      assert Integrity.check() == :ok
    end

    test "not enough coins: no duel row at all", %{a: a, b: b} do
      assert {:error, :insufficient_coins} =
               Contests.create_challenge(a, %{
                 "opponent_id" => b.id,
                 "sport" => "wnba",
                 "draft_starts_at" => future_iso(),
                 "stake_coins" => 1_001
               })

      assert Repo.aggregate(Duel, :count) == 0
      assert Coins.balance(a.id) == 1_000
    end

    test "a friendly (stake 0) moves nothing", %{a: a, b: b} do
      challenge(a, b)
      assert Coins.balance(a.id) == 1_000
      assert Contests.expected_escrow_coins() == 0
    end

    test "a stake above the cap is rejected", %{a: a, b: b} do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Contests.create_challenge(a, %{
                 "opponent_id" => b.id,
                 "sport" => "wnba",
                 "draft_starts_at" => future_iso(),
                 "stake_coins" => 10_001
               })

      assert %{stake_coins: _} = errors_on(changeset)
    end
  end

  describe "accept / decline / cancel (B3, B5, B7)" do
    test "accepting stakes the opponent too", %{a: a, b: b} do
      duel = challenge(a, b, %{"stake_coins" => 250})
      assert {:ok, _} = Contests.accept_challenge(b, duel.id)

      assert Coins.balance(a.id) == 750
      assert Coins.balance(b.id) == 750
      assert Contests.expected_escrow_coins() == 500
      assert Integrity.check() == :ok
    end

    test "an opponent who can't cover the stake can't accept; the duel stays pending", %{a: a} do
      poor = user("poor")
      befriend(a, poor)
      duel = challenge(a, poor, %{"stake_coins" => 250})

      assert {:error, :insufficient_coins} = Contests.accept_challenge(poor, duel.id)
      assert Repo.get(Duel, duel.id).status == "pending"
      assert Coins.balance(a.id) == 750
      assert Integrity.check() == :ok
    end

    test "declining refunds the challenger", %{a: a, b: b} do
      duel = challenge(a, b, %{"stake_coins" => 250})
      assert {:ok, _} = Contests.decline_challenge(b, duel.id)

      assert Coins.balance(a.id) == 1_000
      assert Contests.expected_escrow_coins() == 0
      assert Integrity.check() == :ok
    end

    test "cancelling refunds the challenger", %{a: a, b: b} do
      duel = challenge(a, b, %{"stake_coins" => 250})
      assert {:ok, _} = Contests.cancel_challenge(a, duel.id)

      assert Coins.balance(a.id) == 1_000
      assert Integrity.check() == :ok
    end
  end

  describe "counter (B8)" do
    test "refunds the original challenger; the counter-er stakes the new terms", %{a: a, b: b} do
      duel = challenge(a, b, %{"stake_coins" => 250})
      assert Coins.balance(a.id) == 750

      assert {:ok, counter} =
               Contests.counter_challenge(b, duel.id, %{
                 "sport" => "wnba",
                 "draft_starts_at" => future_iso(),
                 "stake_coins" => 100
               })

      assert counter.stake_coins == 100
      assert Coins.balance(a.id) == 1_000
      assert Coins.balance(b.id) == 900
      assert Contests.expected_escrow_coins() == 100
      assert Integrity.check() == :ok
    end
  end

  describe "rematch (B9)" do
    test "copies the stake and escrows the tapper's", %{a: a, b: b} do
      duel = challenge(a, b, %{"stake_coins" => 150})
      {:ok, _} = Contests.accept_challenge(b, duel.id)
      settle_decisively(duel, a, b)

      # a won the first duel (1000 - 150 + 300 = 1150); b lost (850).
      assert Coins.balance(a.id) == 1_150
      assert Coins.balance(b.id) == 850

      assert {:ok, rematch} = Contests.rematch(b, duel.id)
      assert rematch.stake_coins == 150
      assert Coins.balance(b.id) == 700
      assert Contests.expected_escrow_coins() == 150
      assert Integrity.check() == :ok
    end
  end

  describe "group duels (B2, B4, B6, B10)" do
    test "host stakes at creation; each seat stakes on accept", %{a: h} do
      [i1, i2] = invitees(h, 2)
      duel = group(h, [i1, i2], %{"stake_coins" => 100})

      assert Coins.balance(h.id) == 900
      assert Contests.expected_escrow_coins() == 100

      assert {:ok, _} = Contests.accept_challenge(i1, duel.id)
      assert Coins.balance(i1.id) == 900
      assert Contests.expected_escrow_coins() == 200

      # The last seat declining leaves 2 accepted -> the duel starts; the
      # decliner never staked, so nothing moves for them.
      assert {:ok, started} = Contests.decline_challenge(i2, duel.id)
      assert started.status == "accepted"
      assert Coins.balance(i2.id) == 1_000
      assert Contests.expected_escrow_coins() == 200
      assert Integrity.check() == :ok
    end

    test "a seat that can't cover the stake stays invited", %{a: h} do
      [i1] = invitees(h, 1)
      poor = user("gpoor")
      befriend(h, poor)
      duel = group_raw(h, [i1, poor], %{"stake_coins" => 100})

      assert {:error, :insufficient_coins} = Contests.accept_challenge(poor, duel.id)

      seat = Enum.find(Contests.list_participants(duel.id), &(&1.user_id == poor.id))
      assert seat.status == "invited"
      assert Integrity.check() == :ok
    end

    test "a collapse refunds everyone who staked (B6)", %{a: h} do
      [i1, i2] = invitees(h, 2)
      duel = group(h, [i1, i2], %{"stake_coins" => 100})
      {:ok, _} = Contests.decline_challenge(i1, duel.id)

      # Second decline drops the group under 2 live seats -> cancelled.
      assert {:ok, cancelled} = Contests.decline_challenge(i2, duel.id)
      assert cancelled.status == "cancelled"
      assert Coins.balance(h.id) == 1_000
      assert Contests.expected_escrow_coins() == 0
      assert Integrity.check() == :ok
    end

    test "force-start moves no coins (undecided seats never staked)", %{a: h} do
      [i1, i2] = invitees(h, 2)
      duel = group(h, [i1, i2], %{"stake_coins" => 100})
      {:ok, _} = Contests.accept_challenge(i1, duel.id)

      assert {:ok, started} = Contests.start_with_group(h, duel.id)
      assert started.status == "accepted"
      assert Coins.balance(i2.id) == 1_000
      assert Contests.expected_escrow_coins() == 200
      assert Integrity.check() == :ok
    end
  end

  describe "draft cancelled (B13)" do
    test "refunds every staked player", %{a: a, b: b} do
      duel = challenge(a, b, %{"stake_coins" => 250})
      {:ok, _} = Contests.accept_challenge(b, duel.id)

      assert {:ok, cancelled} = Contests.cancel_drafting(duel.id)
      assert cancelled.status == "cancelled"
      assert Coins.balance(a.id) == 1_000
      assert Coins.balance(b.id) == 1_000
      assert Contests.expected_escrow_coins() == 0
      assert Integrity.check() == :ok
    end
  end

  describe "settlement (B14, B15, B16)" do
    test "the winner takes the pot", %{a: a, b: b} do
      duel = challenge(a, b, %{"stake_coins" => 250})
      {:ok, _} = Contests.accept_challenge(b, duel.id)
      to_drafted(duel)
      with_rosters(duel, player("Star Wing"), player("Bench Guard"))

      assert {:ok, _result, settled} = Settlement.settle_duel(duel.id)
      assert settled.winner_id == a.id
      assert Coins.balance(a.id) == 1_250
      assert Coins.balance(b.id) == 750
      assert Contests.expected_escrow_coins() == 0
      assert Integrity.check() == :ok
    end

    test "a 1v1 tie sends both stakes home", %{a: a, b: b} do
      duel = challenge(a, b, %{"stake_coins" => 250})
      {:ok, _} = Contests.accept_challenge(b, duel.id)
      to_drafted(duel)
      with_rosters(duel, player("Bench A"), player("Bench B"))

      assert {:ok, result, _settled} = Settlement.settle_duel(duel.id)
      assert result.is_tie
      assert Coins.balance(a.id) == 1_000
      assert Coins.balance(b.id) == 1_000
      assert Integrity.check() == :ok
    end

    test "a group tie splits the pot across the top; the remainder burns", %{a: h} do
      [i1, i2] = invitees(h, 2)
      duel = group(h, [i1, i2], %{"stake_coins" => 25})
      {:ok, _} = Contests.accept_challenge(i1, duel.id)
      {:ok, _} = Contests.accept_challenge(i2, duel.id)

      duel = Repo.get(Duel, duel.id)
      to_drafted(duel)
      {:ok, draft} = Drafts.get_or_create_draft_for_duel(duel)
      insert_pick(draft, h, player("Star One"), 1)
      insert_pick(draft, i1, player("Star Two"), 2)
      insert_pick(draft, i2, player("Bench Three"), 3)

      # h and i1 tie at 50: pot 75 -> 37 each, 1 coin burned.
      assert {:ok, result, _settled} = Settlement.settle_duel(duel.id)
      assert result.is_tie
      assert Coins.balance(h.id) == 1_012
      assert Coins.balance(i1.id) == 1_012
      assert Coins.balance(i2.id) == 975
      assert Contests.expected_escrow_coins() == 0
      assert Integrity.check() == :ok
    end

    test "double settle can't double-pay (idempotent settle key)", %{a: a, b: b} do
      duel = challenge(a, b, %{"stake_coins" => 250})
      {:ok, _} = Contests.accept_challenge(b, duel.id)
      to_drafted(duel)
      with_rosters(duel, player("Star Q"), player("Bench Q"))

      assert {:ok, _, _} = Settlement.settle_duel(duel.id)
      assert {:ok, %Duel{status: "settled"}} = Settlement.settle_duel(duel.id)
      assert Coins.balance(a.id) == 1_250
    end
  end

  # --- helpers ---------------------------------------------------------------

  defp challenge(challenger, opponent, attrs \\ %{}) do
    {:ok, duel} =
      Contests.create_challenge(
        challenger,
        Map.merge(
          %{"opponent_id" => opponent.id, "sport" => "wnba", "draft_starts_at" => future_iso()},
          attrs
        )
      )

    duel
  end

  defp group(host, invitee_users, attrs) do
    {:ok, duel} = group_result(host, invitee_users, attrs)
    duel
  end

  defp group_raw(host, invitee_users, attrs) do
    {:ok, duel} = group_result(host, invitee_users, attrs)
    duel
  end

  defp group_result(host, invitee_users, attrs) do
    Contests.create_challenge(
      host,
      Map.merge(
        %{
          "opponent_ids" => Enum.map(invitee_users, & &1.id),
          "sport" => "wnba",
          "draft_starts_at" => future_iso()
        },
        attrs
      )
    )
  end

  defp invitees(host, n) do
    for i <- 1..n do
      u = user("inv#{i}#{System.unique_integer([:positive])}")
      befriend(host, u)
      {:ok, _} = Coins.grant_signup(u.id)
      u
    end
  end

  defp to_drafted(duel) do
    past = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)

    duel
    |> Duel.finish_changeset(%{
      status: "drafted",
      scoring_window_start: DateTime.add(past, -3600),
      scoring_window_end: past
    })
    |> Repo.update!()
  end

  defp settle_decisively(duel, _a, _b) do
    duel = Repo.get(Duel, duel.id)
    to_drafted(duel)
    with_rosters(duel, player("Star R"), player("Bench R"))
    {:ok, _, _} = Settlement.settle_duel(duel.id)
  end

  defp with_rosters(duel, challenger_player, opponent_player) do
    {:ok, draft} = Drafts.get_or_create_draft_for_duel(duel)
    insert_pick(draft, %{id: duel.challenger_id}, challenger_player, 1)
    insert_pick(draft, %{id: duel.opponent_id}, opponent_player, 2)
    draft
  end

  defp insert_pick(draft, user, player, pick_number) do
    Repo.insert!(%Pick{
      draft_id: draft.id,
      user_id: user.id,
      player_id: player.id,
      pick_number: pick_number,
      slot: "G1",
      auto_picked: false
    })
  end

  defp player(name) do
    Repo.insert!(%Player{
      sport: "wnba",
      external_id: "coin-test-" <> String.replace(name, " ", "-"),
      name: name,
      team: "TST",
      position: "PG",
      projection: 10.0
    })
  end

  defp befriend(x, y) do
    Repo.insert!(%Friendship{requester_id: x.id, addressee_id: y.id, status: "accepted"})
  end

  defp future_iso do
    DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{
        "username" => "cd#{name}",
        "email" => "cd-#{name}@example.com",
        "password" => "password123"
      })

    u
  end
end
