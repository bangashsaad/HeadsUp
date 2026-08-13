defmodule HeadsUp.ContestsJanitorTest do
  # async: false — starts a real GenServer that writes through the shared repo.
  use HeadsUp.DataCase, async: false

  alias HeadsUp.{Accounts, Contests, Repo}
  alias HeadsUp.Contests.{Duel, Janitor}
  alias HeadsUp.Social.Friendship

  setup do
    a = user("jana")
    b = user("janb")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
    %{a: a, b: b}
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  # A pending challenge whose draft time is long past — exactly what the
  # janitor exists to clear, and what piled up in production while it slept.
  defp stale_pending(a, b) do
    {:ok, duel} =
      Contests.create_challenge(a, %{
        "sport" => "wnba",
        "opponent_id" => b.id,
        "roster_size" => 5,
        "draft_starts_at" => DateTime.utc_now() |> DateTime.add(1800, :second) |> DateTime.to_iso8601()
      })

    past = DateTime.utc_now() |> DateTime.add(-48 * 3600, :second) |> DateTime.truncate(:second)

    duel
    |> Ecto.Changeset.change(draft_starts_at: past)
    |> Repo.update!()
  end

  test "the first sweep runs near boot, not a full interval later", %{a: a, b: b} do
    duel = stale_pending(a, b)

    # The bug this pins: production scales to zero, so a first tick an hour out
    # never fired. A huge interval with a short first delay must still sweep.
    # A second, differently-named instance: the app supervisor already runs one.
    start_supervised!({Janitor, name: :janitor_boot_test, first_sweep_ms: 10, interval_ms: :timer.hours(24)})

    assert eventually(fn -> Repo.get(Duel, duel.id).status == "cancelled" end),
           "janitor did not sweep on boot — it only cleans if the first tick is short"
  end

  test "a stale pending duel is expired and its stake refunded", %{a: a, b: b} do
    duel = stale_pending(a, b)

    assert %{pending: 1} = Contests.expire_stale(24)
    assert Repo.get(Duel, duel.id).status == "cancelled"
  end

  test "a fresh pending duel is left alone", %{a: a, b: b} do
    {:ok, duel} =
      Contests.create_challenge(a, %{
        "sport" => "wnba",
        "opponent_id" => b.id,
        "roster_size" => 5,
        "draft_starts_at" => DateTime.utc_now() |> DateTime.add(1800, :second) |> DateTime.to_iso8601()
      })

    assert %{pending: 0} = Contests.expire_stale(24)
    assert Repo.get(Duel, duel.id).status == "pending"
  end

  defp eventually(fun, tries \\ 100) do
    cond do
      fun.() -> true
      tries <= 0 -> false
      true ->
        Process.sleep(20)
        eventually(fun, tries - 1)
    end
  end
end
