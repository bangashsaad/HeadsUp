defmodule HeadsUp.Settlement.Stats.NflEspnTest do
  use ExUnit.Case, async: false

  alias HeadsUp.Settlement.Stats.NflEspn
  alias HeadsUp.Settlement.Window
  alias HeadsUp.Sports.Player

  # Stub Client: scoreboard + summary read canned responses from the process dict.
  defmodule StubClient do
    def scoreboard(_sport, ymd), do: Process.get({:scoreboard, ymd}, {:ok, %{"events" => []}})
    def summary(_sport, id), do: Process.get({:summary, to_string(id)}, {:error, :unset})
  end

  setup do
    prev = Application.get_env(:heads_up, NflEspn)
    Application.put_env(:heads_up, NflEspn, client: StubClient)
    on_exit(fn -> Application.put_env(:heads_up, NflEspn, prev) end)
    :ok
  end

  # ET day 2026-08-06 as a UTC window (the code uses a fixed ET = UTC-4).
  defp window do
    %Window{sport: "nfl", opens_at: ~U[2026-08-06 04:00:00Z], closes_at: ~U[2026-08-07 03:59:59Z], duel_id: 1}
  end

  defp event(id, status, state) do
    %{"id" => id, "date" => "2026-08-07T00:00Z", "status" => %{"type" => %{"name" => status, "state" => state}}}
  end

  defp athlete(id, name, stats), do: %{"athlete" => %{"id" => id, "displayName" => name}, "stats" => stats}

  # One game's box score. Mahomes appears in BOTH passing and rushing, which is
  # the case that has to accumulate rather than overwrite.
  defp summary_body do
    {:ok,
     %{
       "header" => %{
         "id" => "401772798",
         "competitions" => [
           %{
             "status" => %{"type" => %{"state" => "post", "shortDetail" => "Final"}},
             "competitors" => [
               %{"team" => %{"abbreviation" => "KC"}, "score" => "13", "homeAway" => "home"}
             ]
           }
         ]
       },
       "boxscore" => %{
         "players" => [
           %{
             "team" => %{"abbreviation" => "KC", "displayName" => "Kansas City"},
             "statistics" => [
               %{
                 "name" => "passing",
                 "labels" => ["C/ATT", "YDS", "AVG", "TD", "INT", "SACKS", "QBR", "RTG"],
                 "athletes" => [
                   athlete("3139477", "Patrick Mahomes", ~w(16/28 189 6.8 0 1 5-21 56.1 62.9))
                 ]
               },
               %{
                 "name" => "rushing",
                 "labels" => ["CAR", "YDS", "AVG", "TD", "LONG"],
                 "athletes" => [athlete("3139477", "Patrick Mahomes", ~w(2 15 7.5 1 12))]
               },
               %{
                 "name" => "receiving",
                 "labels" => ["REC", "YDS", "AVG", "TD", "LONG", "TGTS"],
                 "athletes" => [athlete("15847", "Travis Kelce", ~w(7 70 10.0 0 17 9))]
               },
               %{
                 "name" => "fumbles",
                 "labels" => ["FUM", "LOST", "REC"],
                 "athletes" => [athlete("4241457", "Isiah Pacheco", ~w(1 1 0))]
               },
               # Not a scoreable table — must never reach the totals.
               %{
                 "name" => "defensive",
                 "labels" => ["TOT", "SOLO", "SACKS", "TFL", "PD", "QB HTS", "TD"],
                 "athletes" => [athlete("3122123", "Chris Jones", ~w(4 3 2 1 0 3 0))]
               }
             ]
           }
         ]
       }
     }}
  end

  defp players do
    [
      %Player{id: 1, sport: "nfl", external_id: "3139477", name: "Patrick Mahomes", position: "QB"},
      %Player{id: 2, sport: "nfl", external_id: "15847", name: "Travis Kelce", position: "TE"},
      %Player{id: 3, sport: "nfl", external_id: "4241457", name: "Isiah Pacheco", position: "RB"},
      %Player{id: 4, sport: "nfl", external_id: "9999999", name: "Did Not Play", position: "WR"}
    ]
  end

  defp stage_final do
    Process.put({:scoreboard, "20260806"}, {:ok, %{"events" => [event("401772798", "STATUS_FINAL", "post")]}})
    Process.put({:summary, "401772798"}, summary_body())
  end

  describe "stats_final?/1" do
    test "waits while a game is still in progress" do
      Process.put({:scoreboard, "20260806"}, {:ok, %{"events" => [event("1", "STATUS_IN_PROGRESS", "in")]}})
      refute NflEspn.stats_final?(window())
    end

    test "is true once every in-window game is final" do
      stage_final()
      assert NflEspn.stats_final?(window())
    end

    test "an empty slate is final, not a stall" do
      assert NflEspn.stats_final?(window())
    end

    test "an unreadable scoreboard defers instead of settling on partial data" do
      Process.put({:scoreboard, "20260806"}, {:error, :timeout})
      refute NflEspn.stats_final?(window())
    end
  end

  describe "fetch_stats/2" do
    setup do
      stage_final()
      :ok
    end

    test "sums a quarterback across the passing and rushing tables" do
      lines = NflEspn.fetch_stats(players(), window())
      mahomes = lines[1]

      assert mahomes["passing_yards"] == 189
      assert mahomes["interception"] == 1
      assert mahomes["rushing_yards"] == 15
      assert mahomes["rushing_td"] == 1
    end

    test "scores a receiver whose ESPN game log is empty" do
      # The reason this provider reads box scores at all — Kelce has no log.
      lines = NflEspn.fetch_stats(players(), window())

      assert lines[2]["reception"] == 7
      assert lines[2]["receiving_yards"] == 70
    end

    test "counts a lost fumble" do
      lines = NflEspn.fetch_stats(players(), window())
      assert lines[3]["fumble_lost"] == 1
    end

    test "a player who did not appear gets a full zero line, not a missing key" do
      lines = NflEspn.fetch_stats(players(), window())

      assert lines[4]["passing_yards"] == 0
      assert lines[4]["reception"] == 0
      assert lines[4]["fumble_lost"] == 0
    end

    test "every drafted player is present in the result" do
      lines = NflEspn.fetch_stats(players(), window())
      assert Map.keys(lines) |> Enum.sort() == [1, 2, 3, 4]
    end

    test "an unreadable box score zeroes the slate rather than crashing settlement" do
      Process.put({:summary, "401772798"}, {:error, :timeout})
      lines = NflEspn.fetch_stats(players(), window())

      assert lines[1]["passing_yards"] == 0
    end
  end

  describe "fetch_live_stats/2" do
    test "counts a game in progress that fetch_stats would skip" do
      Process.put({:scoreboard, "20260806"}, {:ok, %{"events" => [event("401772798", "STATUS_IN_PROGRESS", "in")]}})
      Process.put({:summary, "401772798"}, summary_body())

      assert NflEspn.fetch_live_stats(players(), window())[1]["passing_yards"] == 189
      assert NflEspn.fetch_stats(players(), window())[1]["passing_yards"] == 0
    end

    test "a game that has not kicked off contributes nothing" do
      Process.put({:scoreboard, "20260806"}, {:ok, %{"events" => [event("401772798", "STATUS_SCHEDULED", "pre")]}})
      Process.put({:summary, "401772798"}, summary_body())

      assert NflEspn.fetch_live_stats(players(), window())[1]["passing_yards"] == 0
    end
  end
end
