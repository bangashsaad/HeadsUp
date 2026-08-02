defmodule HeadsUp.ContestsWeekSlateTest do
  # async: false — these tests override the app-env slate client.
  use HeadsUp.DataCase, async: false

  alias HeadsUp.{Accounts, Contests, Drafts, Repo}
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Social.Friendship
  alias HeadsUp.Sports.{Player, Slate}

  defmodule StubSlateClient do
    def scoreboard(_sport, _range, _extra \\ []) do
      Process.get(:slate_events, {:ok, %{"events" => []}})
    end
  end

  setup do
    Application.put_env(:heads_up, :slate_client, StubSlateClient)
    on_exit(fn -> Application.delete_env(:heads_up, :slate_client) end)

    a = user("weeka")
    b = user("weekb")
    Repo.insert!(%Friendship{requester_id: a.id, addressee_id: b.id, status: "accepted"})
    %{a: a, b: b}
  end

  defp user(name) do
    {:ok, u} =
      Accounts.register_user(%{"username" => name, "email" => "#{name}@example.com", "password" => "password123"})

    u
  end

  defp seed_players(teams, n) do
    for i <- 1..n do
      Repo.insert!(%Player{
        sport: "nfl",
        external_id: "#{7_700_000 + i}",
        name: "NFL Player #{i}",
        team: Enum.at(teams, rem(i, length(teams))),
        position: Enum.at(~w(QB RB WR TE WR), rem(i, 5)),
        projection: 20.0 - i * 0.01
      })
    end
  end

  # An NFL event carries its season type and week — that pair is the slate.
  defp game_on(date, teams, season_type, week, state \\ "pre") do
    %{
      "date" => "#{Date.to_iso8601(date)}T23:00Z",
      "status" => %{"type" => %{"state" => state}},
      "season" => %{"type" => season_type},
      "week" => %{"number" => week},
      "competitions" => [%{"competitors" => Enum.map(teams, &%{"team" => %{"abbreviation" => &1}})}]
    }
  end

  defp stub_games(events), do: Process.put(:slate_events, {:ok, %{"events" => events}})

  defp create(a, b, extra) do
    Contests.create_challenge(
      a,
      Map.merge(
        %{
          "sport" => "nfl",
          "opponent_id" => b.id,
          "roster_size" => 5,
          "draft_starts_at" => DateTime.utc_now() |> DateTime.add(1800, :second) |> DateTime.to_iso8601()
        },
        extra
      )
    )
  end

  # A football week spread across three days, the shape a real NFL week has.
  defp stub_week_2 do
    thu = Date.add(Slate.today(), 2)
    sun = Date.add(Slate.today(), 5)
    mon = Date.add(Slate.today(), 6)

    stub_games([
      game_on(thu, ["AAA", "BBB"], 1, 2),
      game_on(sun, ["CCC", "DDD"], 1, 2),
      game_on(mon, ["EEE", "FFF"], 1, 2)
    ])

    seed_players(~w(AAA BBB CCC DDD EEE FFF), 60)
    {thu, sun, mon}
  end

  describe "Slate.weeks/2" do
    test "groups the feed by ESPN week and keeps only days with games" do
      {thu, sun, mon} = stub_week_2()

      assert {:ok, [week]} = Slate.weeks("nfl")
      assert week.key == "1-2"
      assert week.label == "Preseason Wk 2"
      assert week.dates == [thu, sun, mon]
      assert week.games == 3
      assert length(week.teams) == 6
    end

    test "labels regular season and playoff weeks differently" do
      d = Date.add(Slate.today(), 2)
      stub_games([game_on(d, ["AAA", "BBB"], 2, 4), game_on(d, ["CCC", "DDD"], 3, 1)])

      assert {:ok, weeks} = Slate.weeks("nfl")
      labels = weeks |> Enum.map(& &1.label) |> Enum.sort()
      assert labels == ["Playoffs Wk 1", "Week 4"]
    end

    test "a week whose games have all kicked off is not pickable" do
      d = Date.add(Slate.today(), 1)
      stub_games([game_on(d, ["AAA", "BBB"], 2, 1, "in")])

      assert {:ok, []} = Slate.weeks("nfl")
    end

    test "only football is week-shaped" do
      assert Slate.week_shaped?("nfl")
      refute Slate.week_shaped?("wnba")
      refute Slate.week_shaped?("mlb")
    end
  end

  describe "creating a football duel" do
    test "defaults to the first pickable week and stores every one of its days", %{a: a, b: b} do
      {thu, sun, mon} = stub_week_2()

      assert {:ok, duel} = create(a, b, %{})
      assert duel.slate_kind == "week"
      assert duel.slate_dates == [thu, sun, mon]
      # slate_date stays the earliest day, for anything predating week slates.
      assert duel.slate_date == thu
    end

    test "honours an explicitly picked week", %{a: a, b: b} do
      thu = Date.add(Slate.today(), 2)
      later = Date.add(Slate.today(), 9)

      stub_games([game_on(thu, ["AAA", "BBB"], 1, 2), game_on(later, ["CCC", "DDD"], 1, 3)])
      seed_players(~w(AAA BBB CCC DDD), 60)

      assert {:ok, duel} = create(a, b, %{"slate_week" => "1-3"})
      assert duel.slate_dates == [later]
    end

    test "rejects a week that isn't on the board", %{a: a, b: b} do
      stub_week_2()
      assert {:error, msg} = create(a, b, %{"slate_week" => "2-17"})
      assert msg =~ "isn't open for drafting"
    end

    test "rejects a draft scheduled after every game has kicked off", %{a: a, b: b} do
      {_thu, _sun, mon} = stub_week_2()

      late = mon |> Date.add(1) |> DateTime.new!(~T[18:00:00], "Etc/UTC") |> DateTime.to_iso8601()

      assert {:error, msg} = create(a, b, %{"slate_week" => "1-2", "draft_starts_at" => late})
      assert msg =~ "before the next game kicks off"
    end

    test "mid-week is still draftable when later games haven't kicked off", %{a: a, b: b} do
      # Thursday already played; Sunday and Monday have not. Creating a duel on
      # Friday must work — blocking it would kill the whole regular season.
      thu = Date.add(Slate.today(), -1)
      sun = Date.add(Slate.today(), 2)
      mon = Date.add(Slate.today(), 3)

      stub_games([
        game_on(thu, ["AAA", "BBB"], 2, 5, "post"),
        game_on(sun, ["CCC", "DDD"], 2, 5),
        game_on(mon, ["EEE", "FFF"], 2, 5)
      ])

      seed_players(~w(AAA BBB CCC DDD EEE FFF), 60)

      assert {:ok, duel} = create(a, b, %{"slate_week" => "2-5"})
      assert duel.slate_kind == "week"
      # The window still covers the whole week; a Thursday player simply can't
      # be drafted, so those points can't reach anyone's roster.
      assert duel.slate_dates == [thu, sun, mon]
    end

    test "rejects a week too thin for the format", %{a: a, b: b} do
      d = Date.add(Slate.today(), 2)
      stub_games([game_on(d, ["AAA", "BBB"], 1, 2)])
      seed_players(~w(AAA BBB), 4)

      assert {:error, msg} = create(a, b, %{"slate_week" => "1-2"})
      assert msg =~ "too small for this format"
    end

    test "a dead feed falls open to an unscoped duel rather than blocking play", %{a: a, b: b} do
      Process.put(:slate_events, {:error, :down})

      assert {:ok, duel} = create(a, b, %{})
      assert duel.slate_dates == nil
      assert duel.slate_date == nil
    end
  end

  describe "the week freezes the scoring window" do
    test "the window runs from the week's first day through its last", %{a: a, b: b} do
      {thu, _sun, mon} = stub_week_2()

      {:ok, duel} = create(a, b, %{"slate_week" => "1-2"})
      {:ok, _} = Contests.accept_challenge(b, duel.id)
      {:ok, _draft} = Drafts.get_or_create_draft_for_duel(Repo.get(Duel, duel.id))

      assert {:ok, drafted} = Contests.finish_draft(duel.id)

      assert drafted.scoring_window_start == DateTime.new!(thu, ~T[04:00:00], "Etc/UTC")

      assert drafted.scoring_window_end ==
               mon |> DateTime.new!(~T[04:00:00], "Etc/UTC") |> DateTime.add(86_399, :second)
    end

    test "a Monday-night game still falls inside the window" do
      # The window has to reach the END of the last day, not its start —
      # otherwise a Monday 8pm kickoff scores nothing.
      mon = ~D[2026-09-14]
      window_end = mon |> DateTime.new!(~T[04:00:00], "Etc/UTC") |> DateTime.add(86_399, :second)
      kickoff = ~U[2026-09-15 00:15:00Z]

      assert DateTime.compare(kickoff, window_end) == :lt
    end
  end
end
