defmodule HeadsUp.TokenExpiryTest do
  use HeadsUp.DataCase, async: true

  import Ecto.Query

  alias HeadsUp.{Accounts, Repo}
  alias HeadsUp.Accounts.UserToken

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  defp age_token(user, days) do
    past = DateTime.utc_now() |> DateTime.add(-days * 86_400, :second) |> DateTime.truncate(:second)
    from(t in UserToken, where: t.user_id == ^user.id and t.context == "api") |> Repo.update_all(set: [inserted_at: past])
  end

  test "a fresh token authenticates" do
    u = user("fresh")
    token = Accounts.create_user_api_token(u)
    assert %{id: id} = Accounts.get_user_by_api_token(token)
    assert id == u.id
  end

  test "a token past the validity window is dead" do
    u = user("ancient")
    token = Accounts.create_user_api_token(u)
    age_token(u, UserToken.api_token_validity_days() + 1)

    assert Accounts.get_user_by_api_token(token) == nil
  end

  test "using a token slides its expiry forward" do
    u = user("active")
    token = Accounts.create_user_api_token(u)
    # Old enough to be near death, but still valid.
    age_token(u, UserToken.api_token_validity_days() - 1)

    :ok = Accounts.refresh_api_token(token)

    # Now it survives past where the original would have expired.
    age_token_row = Repo.one(from t in UserToken, where: t.user_id == ^u.id, select: t.inserted_at)
    assert DateTime.diff(DateTime.utc_now(), age_token_row) < 60
    assert Accounts.get_user_by_api_token(token)
  end

  test "refresh is throttled — a token used twice in a day isn't rewritten twice" do
    u = user("chatty2")
    token = Accounts.create_user_api_token(u)
    stamp = fn -> Repo.one(from t in UserToken, where: t.user_id == ^u.id, select: t.inserted_at) end

    before = stamp.()
    :ok = Accounts.refresh_api_token(token)
    assert stamp.() == before
  end

  test "pruning deletes expired tokens and leaves live ones" do
    live = user("liveuser")
    dead = user("deaduser")
    live_token = Accounts.create_user_api_token(live)
    Accounts.create_user_api_token(dead)
    age_token(dead, UserToken.api_token_validity_days() + 5)

    assert Accounts.prune_expired_tokens() == 1
    assert Accounts.get_user_by_api_token(live_token)
  end
end
