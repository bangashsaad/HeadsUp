defmodule HeadsUp.ContestsChatTest do
  use HeadsUp.DataCase, async: true

  alias HeadsUp.{Accounts, Contests, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Social.Friendship

  setup do
    a = user("chata")
    b = user("chatb")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})

    {:ok, duel} =
      Contests.create_challenge(a, %{
        "sport" => "wnba",
        "opponent_id" => b.id,
        "roster_size" => 5,
        "draft_starts_at" => DateTime.utc_now() |> DateTime.add(1800, :second) |> DateTime.to_iso8601()
      })

    {:ok, _} = Contests.accept_challenge(b, duel.id)
    %{a: a, b: b, duel: Repo.get(Duel, duel.id)}
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  test "players can talk and both read the same thread, oldest first", %{a: a, b: b, duel: duel} do
    {:ok, _} = Contests.post_message(a, duel.id, "Collier ain't saving you tonight")
    {:ok, _} = Contests.post_message(b, duel.id, "She already has 34. Scoreboard.")

    {:ok, thread} = Contests.list_messages(a, duel.id)
    assert Enum.map(thread, & &1.body) == ["Collier ain't saving you tonight", "She already has 34. Scoreboard."]
    assert Enum.map(thread, & &1.username) == ["chata", "chatb"]

    {:ok, same} = Contests.list_messages(b, duel.id)
    assert length(same) == 2
  end

  test "posting broadcasts to the duel's chat topic", %{a: a, duel: duel} do
    Phoenix.PubSub.subscribe(HeadsUp.PubSub, "duel_chat:#{duel.id}")

    {:ok, _} = Contests.post_message(a, duel.id, "Fourth quarter exists my guy")

    assert_receive {:duel_message, %{body: "Fourth quarter exists my guy", username: "chata"}}
  end

  test "an outsider can neither read nor post", %{duel: duel} do
    stranger = user("chatstranger")

    assert {:error, :not_your_duel} = Contests.post_message(stranger, duel.id, "let me in")
    assert {:error, :not_your_duel} = Contests.list_messages(stranger, duel.id)
  end

  test "no talking into a pending challenge", %{a: a, b: b} do
    {:ok, pending} =
      Contests.create_challenge(a, %{
        "sport" => "wnba",
        "opponent_id" => b.id,
        "roster_size" => 5,
        "draft_starts_at" => DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()
      })

    assert {:error, :no_room_yet} = Contests.post_message(a, pending.id, "hello?")
  end

  test "the thread stays open after settlement — receipts are the point", %{a: a, duel: duel} do
    duel |> Ecto.Changeset.change(status: "settled") |> Repo.update!()

    assert {:ok, _} = Contests.post_message(a, duel.id, "Scoreboard. Forever.")
  end

  test "an empty or over-long jab is rejected", %{a: a, duel: duel} do
    assert {:error, %Ecto.Changeset{}} = Contests.post_message(a, duel.id, "   ")
    assert {:error, %Ecto.Changeset{}} = Contests.post_message(a, duel.id, String.duplicate("x", 281))
  end
end
