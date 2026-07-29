defmodule HeadsUp.ChallengeFoundationTest do
  @moduledoc "Backend foundation for the canonical challenge screen."
  use HeadsUp.DataCase, async: true

  alias HeadsUp.{Accounts, Contests, Repo}
  alias HeadsUp.Contests.Participant
  alias HeadsUp.Social.Friendship

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  defp befriend(a, b), do: Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
  defp future, do: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.to_iso8601()

  describe "participant cap" do
    test "a host plus four invitees is allowed (five drafters)" do
      host = user("host")
      invitees = for i <- 1..4, do: user("rival#{i}")
      Enum.each(invitees, &befriend(host, &1))

      assert {:ok, duel} =
               Contests.create_challenge(host, %{
                 "opponent_ids" => Enum.map(invitees, & &1.id),
                 "sport" => "wnba",
                 "draft_starts_at" => future()
               })

      assert length(Contests.list_participants(duel.id)) == 5
    end

    test "a fifth invitee is rejected" do
      host = user("host2")
      invitees = for i <- 1..5, do: user("extra#{i}")
      Enum.each(invitees, &befriend(host, &1))

      assert {:error, msg} =
               Contests.create_challenge(host, %{
                 "opponent_ids" => Enum.map(invitees, & &1.id),
                 "sport" => "wnba",
                 "draft_starts_at" => future()
               })

      assert msg =~ "at most 5 players"
    end

    test "max_seat still means seat indexes 0..4" do
      assert Participant.max_seat() == 4
    end
  end

  describe "default lineup + clocks" do
    test "a challenge with no template gets the canonical 5-slot shape" do
      a = user("deflt")
      b = user("deflt2")
      befriend(a, b)

      assert {:ok, duel} =
               Contests.create_challenge(a, %{"opponent_id" => b.id, "sport" => "wnba", "draft_starts_at" => future()})

      assert duel.lineup_template == "wnba_5"
      assert duel.roster_size == 5
    end

    test "the short clocks are accepted and async is no longer offered" do
      a = user("clock")
      b = user("clock2")
      befriend(a, b)

      for secs <- [15, 30, 60] do
        assert {:ok, _} =
                 Contests.create_challenge(a, %{
                   "opponent_id" => b.id,
                   "sport" => "wnba",
                   "pick_clock_seconds" => secs,
                   "draft_starts_at" => future()
                 })
      end

      # Legacy async values stay VALID so old duels (and rematches cloning
      # them) keep working — they're just never offered in the picker.
      assert {:ok, _} =
               Contests.create_challenge(a, %{
                 "opponent_id" => b.id,
                 "sport" => "wnba",
                 "pick_clock_seconds" => 86_400,
                 "draft_starts_at" => future()
               })

      assert {:error, %Ecto.Changeset{}} =
               Contests.create_challenge(a, %{
                 "opponent_id" => b.id,
                 "sport" => "wnba",
                 "pick_clock_seconds" => 45,
                 "draft_starts_at" => future()
               })
    end
  end

  describe "presence (last-seen)" do
    test "a fresh account is offline until it is touched" do
      u = user("ghosty")
      refute Accounts.online?(u)

      touched = Accounts.touch_last_seen(u)
      assert Accounts.online?(touched)
    end

    test "activity older than the window reads offline" do
      u = user("stale")
      old = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      stale = Ecto.Changeset.change(u, last_seen_at: old) |> Repo.update!()

      refute Accounts.online?(stale)
    end

    test "stamping is throttled — a second immediate touch does not rewrite" do
      u = user("chatty")
      first = Accounts.touch_last_seen(u)
      again = Accounts.touch_last_seen(first)

      assert first.last_seen_at == again.last_seen_at
    end
  end

  describe "slate_player_count/2" do
    test "counts only players on the given teams, and zero for none" do
      for {team, n} <- [{"AAA", 3}, {"BBB", 2}, {"ZZZ", 4}], i <- 1..n do
        Repo.insert!(%HeadsUp.Sports.Player{
          sport: "wnba",
          external_id: "count-#{team}-#{i}",
          name: "P #{team}#{i}",
          team: team,
          position: "G",
          projection: 10.0
        })
      end

      assert Contests.slate_player_count("wnba", ["AAA", "BBB"]) == 5
      assert Contests.slate_player_count("wnba", []) == 0
    end
  end
end
