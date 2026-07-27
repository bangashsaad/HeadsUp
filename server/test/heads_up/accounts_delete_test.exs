defmodule HeadsUp.AccountsDeleteTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.{Accounts, Contests, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Social
  alias HeadsUp.Social.Friendship

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  defp befriend(a, b), do: Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})

  defp challenge(a, b, attrs \\ %{}) do
    {:ok, duel} =
      Contests.create_challenge(
        a,
        Map.merge(
          %{
            "opponent_id" => b.id,
            "sport" => "wnba",
            "draft_starts_at" => DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
          },
          attrs
        )
      )

    duel
  end

  test "the wrong password deletes nothing" do
    u = user("keeper")
    assert {:error, :invalid_current_password} = Accounts.delete_account(u, "wrong-password")
    fresh = Accounts.get_user(u.id)
    assert fresh.username == "keeper"
    assert is_nil(fresh.deleted_at)
  end

  test "deletion scrubs PII, kills tokens, and blocks both login paths" do
    u = user("ghostme")
    token = Accounts.create_user_api_token(u)

    assert {:ok, ghost} = Accounts.delete_account(u, "password123")

    assert ghost.username == "deleted_#{u.id}"
    assert ghost.email == "deleted+#{u.id}@deleted.invalid"
    assert is_nil(ghost.push_token)
    refute is_nil(ghost.deleted_at)

    assert Accounts.get_user_by_api_token(token) == nil
    assert Accounts.get_user_by_email_and_password("ghostme@example.com", "password123") == nil
  end

  test "friendships vanish both directions and the ghost leaves search" do
    u = user("popular")
    f1 = user("friend1")
    f2 = user("friend2")
    befriend(u, f1)
    befriend(f2, u)

    {:ok, _} = Accounts.delete_account(u, "password123")

    assert Social.list_friends(f1) == []
    assert Social.list_friends(f2) == []
    assert Social.search_users("deleted", f1) == []
    assert Social.search_users("popular", f1) == []
  end

  test "their pending challenge is cancelled and the stake comes home" do
    a = user("staker")
    b = user("opp")
    befriend(a, b)
    {:ok, _} = HeadsUp.Coins.grant_signup(a.id)
    before = HeadsUp.Coins.balance(a.id)

    duel = challenge(a, b, %{"stake_coins" => 100})
    assert HeadsUp.Coins.balance(a.id) == before - 100

    {:ok, _} = Accounts.delete_account(a, "password123")

    assert Repo.get(Duel, duel.id).status == "cancelled"
    assert HeadsUp.Coins.balance(a.id) == before
  end

  test "an invite they were sitting on is declined, not left hanging" do
    a = user("hostx")
    b = user("leaver")
    befriend(a, b)
    duel = challenge(a, b)

    {:ok, _} = Accounts.delete_account(b, "password123")

    assert Repo.get(Duel, duel.id).status == "declined"
  end

  test "an accepted duel is cancelled with everyone refunded" do
    a = user("stayer")
    b = user("quitter")
    befriend(a, b)
    {:ok, _} = HeadsUp.Coins.grant_signup(a.id)
    {:ok, _} = HeadsUp.Coins.grant_signup(b.id)
    a_before = HeadsUp.Coins.balance(a.id)
    b_before = HeadsUp.Coins.balance(b.id)

    duel = challenge(a, b, %{"stake_coins" => 250})
    {:ok, _} = Contests.accept_challenge(b, duel.id)

    {:ok, _} = Accounts.delete_account(b, "password123")

    assert Repo.get(Duel, duel.id).status == "cancelled"
    assert HeadsUp.Coins.balance(a.id) == a_before
    assert HeadsUp.Coins.balance(b.id) == b_before
  end

  test "settled history survives under the ghost name" do
    a = user("winner")
    b = user("gone")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    duel =
      Repo.insert!(%Duel{
        challenger_id: a.id,
        opponent_id: b.id,
        sport: "wnba",
        draft_type: "snake",
        lineup_template: "wnba_standard",
        roster_size: 5,
        pick_clock_seconds: 60,
        scoring_rules: %{},
        stake_coins: 0,
        draft_starts_at: now,
        status: "settled",
        winner_id: a.id,
        settled_at: now
      })

    {:ok, _} = Accounts.delete_account(b, "password123")

    fresh = Repo.get(Duel, duel.id)
    assert fresh.status == "settled"
    assert fresh.opponent_id == b.id
    assert Accounts.get_user(b.id).username == "deleted_#{b.id}"
  end
end
