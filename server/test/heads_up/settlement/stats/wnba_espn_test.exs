defmodule HeadsUp.Settlement.Stats.WnbaEspnTest do
  use ExUnit.Case, async: false

  alias HeadsUp.Settlement.Stats.WnbaEspn
  alias HeadsUp.Settlement.Window
  alias HeadsUp.Sports.Player

  # Stub Client: scoreboard/summary read canned responses from the process dict
  # and record which scoreboard days were queried.
  defmodule StubClient do
    def scoreboard(_sport, ymd) do
      Process.put(:queried, [ymd | Process.get(:queried, [])])
      Process.get({:scoreboard, ymd}, {:ok, %{"events" => []}})
    end

    def summary(_sport, id), do: Process.get({:summary, to_string(id)}, {:error, :unset})
  end

  setup do
    prev = Application.get_env(:heads_up, WnbaEspn)
    Application.put_env(:heads_up, WnbaEspn, client: StubClient)
    on_exit(fn -> Application.put_env(:heads_up, WnbaEspn, prev) end)
    :ok
  end

  # ET day 2026-06-28 expressed as a UTC window (ET = UTC-4).
  defp one_day_window do
    %Window{
      sport: "wnba",
      opens_at: ~U[2026-06-28 04:00:00Z],
      closes_at: ~U[2026-06-29 03:59:59Z],
      duel_id: 1
    }
  end

  defp event(id, status), do: %{"id" => id, "date" => "2026-06-28T23:00Z", "status" => %{"type" => %{"name" => status}}}

  defp boxscore(athletes) do
    {:ok,
     %{
       "boxscore" => %{
         "players" => [
           %{"statistics" => [%{"labels" => ~w(MIN PTS FG 3PT FT REB AST TO STL BLK), "athletes" => athletes}]}
         ]
       }
     }}
  end

  # athlete row aligned to the labels above
  defp ath(id, [min, pts, fg, tpt, ft, reb, ast, to, stl, blk]) do
    %{"athlete" => %{"id" => id}, "stats" => [min, pts, fg, tpt, ft, reb, ast, to, stl, blk]}
  end

  defp players do
    [
      %Player{id: 1, sport: "wnba", external_id: "100", name: "Scorer", position: "G"},
      %Player{id: 2, sport: "wnba", external_id: "200", name: "Shooter", position: "F"},
      %Player{id: 3, sport: "wnba", external_id: "300", name: "DNP Player", position: "C"},
      %Player{id: 4, sport: "wnba", external_id: "999", name: "Not In Box", position: "G"}
    ]
  end

  describe "stats_final?/1" do
    test "true when every in-window game is FINAL and its boxscore is reachable" do
      Process.put({:scoreboard, "20260628"}, {:ok, %{"events" => [event("401", "STATUS_FINAL")]}})
      Process.put({:summary, "401"}, boxscore([]))
      assert WnbaEspn.stats_final?(one_day_window())
    end

    test "false when any in-window game is not final (defer)" do
      Process.put(
        {:scoreboard, "20260628"},
        {:ok, %{"events" => [event("401", "STATUS_FINAL"), event("402", "STATUS_SCHEDULED")]}}
      )

      refute WnbaEspn.stats_final?(one_day_window())
    end

    test "true when the window has zero games (nothing to wait for)" do
      Process.put({:scoreboard, "20260628"}, {:ok, %{"events" => []}})
      assert WnbaEspn.stats_final?(one_day_window())
    end

    test "false when a FINAL game's boxscore is unreachable" do
      Process.put({:scoreboard, "20260628"}, {:ok, %{"events" => [event("401", "STATUS_FINAL")]}})
      Process.put({:summary, "401"}, {:error, {:http, 500}})
      refute WnbaEspn.stats_final?(one_day_window())
    end

    test "false when a day's scoreboard cannot be fetched" do
      Process.put({:scoreboard, "20260628"}, {:error, {:transport, :timeout}})
      refute WnbaEspn.stats_final?(one_day_window())
    end

    test "queries every ET day the window spans" do
      multiday = %Window{
        sport: "wnba",
        opens_at: ~U[2026-06-28 04:00:00Z],
        closes_at: ~U[2026-06-30 03:59:59Z],
        duel_id: 1
      }

      WnbaEspn.stats_final?(multiday)
      assert Enum.sort(Process.get(:queried)) == ["20260628", "20260629"]
    end
  end

  describe "team_states/1" do
    test "maps each in-window team to its game's state + detail" do
      live_event =
        event("401", "STATUS_IN_PROGRESS")
        |> put_in(["status", "type", "state"], "in")
        |> put_in(["status", "type", "shortDetail"], "End of 1st")
        |> Map.put("competitions", [
          %{"competitors" => [%{"team" => %{"abbreviation" => "LV"}}, %{"team" => %{"abbreviation" => "NY"}}]}
        ])

      Process.put({:scoreboard, "20260628"}, {:ok, %{"events" => [live_event]}})

      assert WnbaEspn.team_states(one_day_window()) == %{
               "LV" => %{state: "in", detail: "End of 1st"},
               "NY" => %{state: "in", detail: "End of 1st"}
             }
    end

    test "a feed error yields an empty map (chips just don't render)" do
      Process.put({:scoreboard, "20260628"}, {:error, {:transport, :timeout}})
      assert WnbaEspn.team_states(one_day_window()) == %{}
    end
  end

  describe "fetch_stats/2" do
    test "maps stats to player ids, parses 3PT, zeros DNP and not-found, full 7 cats each" do
      athletes = [
        ath("100", ["33", "21", "9-17", "0-0", "3-4", "14", "2", "0", "3", "1"]),
        ath("200", ["38", "17", "6-16", "4-10", "1-1", "1", "2", "1", "0", "0"]),
        # 300 is a DNP — empty stats
        %{"athlete" => %{"id" => "300"}, "stats" => []}
      ]

      Process.put({:scoreboard, "20260628"}, {:ok, %{"events" => [event("401", "STATUS_FINAL")]}})
      Process.put({:summary, "401"}, boxscore(athletes))

      stats = WnbaEspn.fetch_stats(players(), one_day_window())

      assert stats[1] == %{
               "point" => 21,
               "rebound" => 14,
               "assist" => 2,
               "steal" => 3,
               "block" => 1,
               "turnover" => 0,
               "three_made" => 0
             }

      assert stats[2]["point"] == 17
      assert stats[2]["three_made"] == 4
      # DNP and not-found both score a full zero line
      zero = %{"point" => 0, "rebound" => 0, "assist" => 0, "steal" => 0, "block" => 0, "turnover" => 0, "three_made" => 0}
      assert stats[3] == zero
      assert stats[4] == zero
      # every input player present
      assert Map.keys(stats) |> Enum.sort() == [1, 2, 3, 4]
    end

    test "sums a player's stats across multiple in-window games" do
      Process.put(
        {:scoreboard, "20260628"},
        {:ok, %{"events" => [event("401", "STATUS_FINAL"), event("402", "STATUS_FINAL")]}}
      )

      Process.put({:summary, "401"}, boxscore([ath("100", ["20", "10", "4-8", "1-2", "0-0", "5", "1", "0", "0", "0"])]))
      Process.put({:summary, "402"}, boxscore([ath("100", ["22", "12", "5-9", "2-3", "0-0", "6", "2", "1", "1", "0"])]))

      stats = WnbaEspn.fetch_stats(players(), one_day_window())
      assert stats[1]["point"] == 22, "10 + 12"
      assert stats[1]["rebound"] == 11, "5 + 6"
      assert stats[1]["three_made"] == 3, "1 + 2"
    end
  end
end
