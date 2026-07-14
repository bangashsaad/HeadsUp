defmodule HeadsUp.ContestsSlateTest do
  # async: false — these tests override the app-env slate client.
  use HeadsUp.DataCase, async: false

  alias HeadsUp.{Accounts, Contests, Drafts, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Social.Friendship
  alias HeadsUp.Sports.{Player, Slate}

  # App-env stub: create_challenge reaches Slate through config. Events come
  # from the process dictionary; the cache is bypassed for any non-default
  # client, so nothing leaks across tests.
  defmodule StubSlateClient do
    def scoreboard(_sport, _range, _extra \\ []) do
      Process.get(:slate_events, {:ok, %{"events" => []}})
    end
  end

  setup do
    Application.put_env(:heads_up, :slate_client, StubSlateClient)
    on_exit(fn -> Application.delete_env(:heads_up, :slate_client) end)

    a = user("slatea")
    b = user("slateb")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
    %{a: a, b: b}
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  # `n` wnba players spread across `teams` — the slate pool the guard counts.
  defp seed_players(teams, n), do: seed_players_offset(teams, n, 0)

  defp seed_players_offset(teams, n, offset) do
    for i <- (offset + 1)..(offset + n) do
      Repo.insert!(%Player{
        sport: "wnba",
        external_id: "slate-#{i}",
        name: "Slate Player #{i}",
        team: Enum.at(teams, rem(i, length(teams))),
        position: Enum.at(~w(G G F F C), rem(i, 5)),
        projection: 50.0 - i * 0.1
      })
    end
  end

  defp game_on(date, teams, state \\ "pre") do
    %{
      "date" => "#{Date.to_iso8601(date)}T23:00Z",
      "status" => %{"type" => %{"state" => state}},
      "competitions" => [%{"competitors" => Enum.map(teams, &%{"team" => %{"abbreviation" => &1}})}]
    }
  end

  defp stub_games(events), do: Process.put(:slate_events, {:ok, %{"events" => events}})

  defp create(a, b, attrs) do
    Contests.create_challenge(
      a,
      Map.merge(
        %{
          "opponent_id" => b.id,
          "sport" => "wnba",
          "draft_starts_at" => DateTime.utc_now() |> DateTime.add(1800, :second) |> DateTime.to_iso8601()
        },
        attrs
      )
    )
  end

  describe "slate resolution at create" do
    test "an explicit slate day with games and a big enough pool sticks", %{a: a, b: b} do
      tomorrow = Date.add(Slate.today(), 1)
      stub_games([game_on(tomorrow, ["AAA", "BBB"]), game_on(tomorrow, ["CCC", "DDD"])])
      seed_players(~w(AAA BBB CCC DDD), 30)

      assert {:ok, duel} = create(a, b, %{"slate_date" => Date.to_iso8601(tomorrow)})
      assert duel.slate_date == tomorrow
    end

    test "a day with no games is rejected", %{a: a, b: b} do
      tomorrow = Date.add(Slate.today(), 1)
      stub_games([])

      assert {:error, msg} = create(a, b, %{"slate_date" => Date.to_iso8601(tomorrow)})
      assert msg =~ "no WNBA games"
    end

    test "a slate too small for the format is rejected", %{a: a, b: b} do
      tomorrow = Date.add(Slate.today(), 1)
      stub_games([game_on(tomorrow, ["AAA", "BBB"])])
      # wnba_standard = 6 slots; 1v1 needs 6*2*2 = 24 — seed only 10.
      seed_players(~w(AAA BBB), 10)

      assert {:error, msg} = create(a, b, %{"slate_date" => Date.to_iso8601(tomorrow)})
      assert msg =~ "too small"
    end

    test "yesterday is rejected without touching the feed", %{a: a, b: b} do
      yesterday = Date.add(Slate.today(), -1)
      assert {:error, msg} = create(a, b, %{"slate_date" => Date.to_iso8601(yesterday)})
      assert msg =~ "already happened"
    end

    test "past the one-week horizon is rejected", %{a: a, b: b} do
      far = Date.add(Slate.today(), 9)
      assert {:error, msg} = create(a, b, %{"slate_date" => Date.to_iso8601(far)})
      assert msg =~ "closer day"
    end

    test "a draft scheduled after the slate day is rejected", %{a: a, b: b} do
      tomorrow = Date.add(Slate.today(), 1)
      stub_games([game_on(tomorrow, ["AAA", "BBB"])])
      seed_players(~w(AAA BBB), 30)

      day_after_iso =
        DateTime.utc_now() |> DateTime.add(3 * 86_400, :second) |> DateTime.to_iso8601()

      assert {:error, msg} =
               create(a, b, %{"slate_date" => Date.to_iso8601(tomorrow), "draft_starts_at" => day_after_iso})

      assert msg =~ "on or before the slate day"
    end

    test "garbage slate dates are rejected", %{a: a, b: b} do
      assert {:error, msg} = create(a, b, %{"slate_date" => "not-a-date"})
      assert msg =~ "real date"
    end

    test "no slate given defaults to the first viable day with games", %{a: a, b: b} do
      day_after = Date.add(Slate.today(), 2)
      stub_games([game_on(day_after, ["AAA", "BBB"])])
      seed_players(~w(AAA BBB), 30)

      assert {:ok, duel} = create(a, b, %{})
      assert duel.slate_date == day_after
    end

    test "a tipped-out day is rejected — no drafting known stat lines", %{a: a, b: b} do
      today = Slate.today()
      stub_games([game_on(today, ["AAA", "BBB"], "post"), game_on(today, ["CCC", "DDD"], "in")])
      seed_players(~w(AAA BBB CCC DDD), 30)

      assert {:error, msg} = create(a, b, %{"slate_date" => Date.to_iso8601(today)})
      assert msg =~ "already tipped"
    end

    test "the default slate never lands before the draft day", %{a: a, b: b} do
      tomorrow = Date.add(Slate.today(), 1)
      in_three = Date.add(Slate.today(), 3)

      stub_games([
        game_on(tomorrow, ["AAA", "BBB"]),
        game_on(in_three, ["CCC", "DDD"]),
        game_on(in_three, ["EEE", "FFF"])
      ])

      seed_players(~w(AAA BBB), 30)
      seed_players_offset(~w(CCC DDD EEE FFF), 30, 100)

      draft_iso = DateTime.utc_now() |> DateTime.add(3 * 86_400, :second) |> DateTime.to_iso8601()
      assert {:ok, duel} = create(a, b, %{"draft_starts_at" => draft_iso})

      # Tomorrow has games but the draft is 3 days out — the default skips it.
      assert duel.slate_date == in_three
    end

    test "feed down: an explicit choice is kept, a default is skipped (fail open)", %{a: a, b: b} do
      Process.put(:slate_events, {:error, {:transport, :timeout}})
      tomorrow = Date.add(Slate.today(), 1)

      assert {:ok, kept} = create(a, b, %{"slate_date" => Date.to_iso8601(tomorrow)})
      assert kept.slate_date == tomorrow

      assert {:ok, legacy} = create(a, b, %{})
      assert legacy.slate_date == nil
    end

    test "group creates resolve the slate too", %{a: a, b: b} do
      c = user("slatec")
      Repo.insert!(%Friendship{requester_id: a.id, addressee_id: c.id, status: "accepted"})

      tomorrow = Date.add(Slate.today(), 1)
      stub_games([game_on(tomorrow, ["AAA", "BBB"]), game_on(tomorrow, ["CCC", "DDD"])])
      # 3 players × 6 slots × 2 = 36 needed
      seed_players(~w(AAA BBB CCC DDD), 40)

      assert {:ok, duel} =
               Contests.create_challenge(a, %{
                 "opponent_ids" => [b.id, c.id],
                 "sport" => "wnba",
                 "slate_date" => Date.to_iso8601(tomorrow),
                 "draft_starts_at" => DateTime.utc_now() |> DateTime.add(1800, :second) |> DateTime.to_iso8601()
               })

      assert duel.slate_date == tomorrow
    end
  end

  describe "the slate freezes the scoring window" do
    test "finish_draft pins the window to the slate's ET day", %{a: a, b: b} do
      tomorrow = Date.add(Slate.today(), 1)
      stub_games([game_on(tomorrow, ["AAA", "BBB"]), game_on(tomorrow, ["CCC", "DDD"])])
      seed_players(~w(AAA BBB CCC DDD), 30)

      {:ok, duel} = create(a, b, %{"slate_date" => Date.to_iso8601(tomorrow)})
      {:ok, _} = Contests.accept_challenge(b, duel.id)
      {:ok, _draft} = Drafts.get_or_create_draft_for_duel(Repo.get(Duel, duel.id))

      assert {:ok, drafted} = Contests.finish_draft(duel.id)
      assert drafted.scoring_window_start == DateTime.new!(tomorrow, ~T[04:00:00], "Etc/UTC")
      assert drafted.scoring_window_end == DateTime.new!(tomorrow, ~T[04:00:00], "Etc/UTC") |> DateTime.add(86_399, :second)
    end

    test "a slate-less duel keeps the legacy anchored-at-completion window", %{a: a, b: b} do
      Process.put(:slate_events, {:error, :down})
      {:ok, duel} = create(a, b, %{})
      assert duel.slate_date == nil

      {:ok, _} = Contests.accept_challenge(b, duel.id)
      assert {:ok, drafted} = Contests.finish_draft(duel.id)

      seconds = DateTime.diff(drafted.scoring_window_end, drafted.scoring_window_start)
      assert seconds == Application.get_env(:heads_up, :scoring_window_seconds, 86_400)
    end
  end

  describe "expire_stale/1 (the Janitor's sweep)" do
    defp age(duel, hours) do
      past = DateTime.utc_now() |> DateTime.add(-hours * 3600, :second) |> DateTime.truncate(:second)
      duel |> Ecto.Changeset.change(draft_starts_at: past) |> Repo.update!()
    end

    test "an unanswered pending challenge past the cutoff is cancelled", %{a: a, b: b} do
      {:ok, duel} = create(a, b, %{})
      age(Repo.get(Duel, duel.id), 30)

      assert %{pending: 1, lobby: 0} = Contests.expire_stale(24)
      assert Repo.get(Duel, duel.id).status == "cancelled"
    end

    test "an accepted duel whose draft never left the lobby is cancelled", %{a: a, b: b} do
      {:ok, duel} = create(a, b, %{})
      {:ok, _} = Contests.accept_challenge(b, duel.id)
      {:ok, _draft} = Drafts.get_or_create_draft_for_duel(Repo.get(Duel, duel.id))
      age(Repo.get(Duel, duel.id), 30)

      assert %{pending: 0, lobby: 1} = Contests.expire_stale(24)
      assert Repo.get(Duel, duel.id).status == "cancelled"
    end

    test "a draft with picks on the board is left alone", %{a: a, b: b} do
      {:ok, duel} = create(a, b, %{})
      {:ok, _} = Contests.accept_challenge(b, duel.id)
      {:ok, draft} = Drafts.get_or_create_draft_for_duel(Repo.get(Duel, duel.id))
      age(Repo.get(Duel, duel.id), 30)

      [p] = seed_players(~w(AAA), 1)

      {:ok, _} =
        Drafts.record_pick(%{
          draft_id: draft.id,
          pick_number: 1,
          user_id: a.id,
          player_id: p.id,
          slot: "G1",
          auto_picked: false
        })

      assert %{pending: 0, lobby: 0} = Contests.expire_stale(24)
      refute Repo.get(Duel, duel.id).status == "cancelled"
    end

    test "a zero-pick but ACTIVE long-clock draft is NOT swept", %{a: a, b: b} do
      {:ok, duel} = create(a, b, %{})
      {:ok, _} = Contests.accept_challenge(b, duel.id)
      {:ok, draft} = Drafts.get_or_create_draft_for_duel(Repo.get(Duel, duel.id))
      {:ok, _} = Drafts.start_active(draft, [a.id, b.id])
      age(Repo.get(Duel, duel.id), 30)

      assert %{pending: 0, lobby: 0} = Contests.expire_stale(24)
      assert Repo.get(Duel, duel.id).status == "drafting"
    end

    test "finish_draft never resurrects a cancelled duel", %{a: a, b: b} do
      {:ok, duel} = create(a, b, %{})
      {:ok, _} = Contests.accept_challenge(b, duel.id)
      {:ok, _} = Contests.cancel_drafting(duel.id)

      assert {:ok, still} = Contests.finish_draft(duel.id)
      assert still.status == "cancelled"
      assert Repo.get(Duel, duel.id).status == "cancelled"
    end

    test "fresh duels are untouched", %{a: a, b: b} do
      {:ok, _duel} = create(a, b, %{})
      assert %{pending: 0, lobby: 0} = Contests.expire_stale(24)
    end

    test "an expired pending challenge sends the stake home", %{a: a, b: b} do
      {:ok, _} = HeadsUp.Coins.grant_signup(a.id)
      before = HeadsUp.Coins.balance(a.id)

      {:ok, duel} = create(a, b, %{"stake_coins" => 100})
      assert HeadsUp.Coins.balance(a.id) == before - 100

      age(Repo.get(Duel, duel.id), 30)
      assert %{pending: 1} = Contests.expire_stale(24)
      assert HeadsUp.Coins.balance(a.id) == before
    end
  end
end
