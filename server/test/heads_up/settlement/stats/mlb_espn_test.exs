defmodule HeadsUp.Settlement.Stats.MlbEspnTest do
  use ExUnit.Case, async: false

  alias HeadsUp.Settlement.Stats.MlbEspn
  alias HeadsUp.Settlement.Window
  alias HeadsUp.Sports.Player

  # Stub Client: scoreboard + gamelog read canned responses from the process dict.
  defmodule StubClient do
    def scoreboard(_sport, ymd), do: Process.get({:scoreboard, ymd}, {:ok, %{"events" => []}})
    def gamelog(_sport, id), do: Process.get({:gamelog, to_string(id)}, {:error, :unset})
  end

  setup do
    prev = Application.get_env(:heads_up, MlbEspn)
    Application.put_env(:heads_up, MlbEspn, client: StubClient)
    on_exit(fn -> Application.put_env(:heads_up, MlbEspn, prev) end)
    :ok
  end

  # ET day 2026-06-28 as a UTC window (ET = UTC-4).
  defp window do
    %Window{sport: "mlb", opens_at: ~U[2026-06-28 04:00:00Z], closes_at: ~U[2026-06-29 03:59:59Z], duel_id: 1}
  end

  defp event(id, status), do: %{"id" => id, "date" => "2026-06-28T17:35Z", "status" => %{"type" => %{"name" => status}}}

  @batting_names ~w(atBats runs hits doubles triples homeRuns RBIs walks hitByPitch strikeouts stolenBases)
  @pitching_names ~w(innings hits runs earnedRuns homeRuns walks strikeouts wins-losses)

  defp batting_log(events) do
    {:ok,
     %{
       "names" => @batting_names,
       "events" => Map.new(events, fn {eid, _} -> {eid, %{"gameDate" => "2026-06-28T17:35Z"}} end),
       "seasonTypes" => [%{"categories" => [%{"events" => Enum.map(events, fn {eid, stats} -> %{"eventId" => eid, "stats" => stats} end)}]}]
     }}
  end

  defp pitching_log(events) do
    {:ok,
     %{
       "names" => @pitching_names,
       "events" => Map.new(events, fn {eid, _} -> {eid, %{"gameDate" => "2026-06-28T17:35Z"}} end),
       "seasonTypes" => [%{"categories" => [%{"events" => Enum.map(events, fn {eid, stats} -> %{"eventId" => eid, "stats" => stats} end)}]}]
     }}
  end

  defp players do
    [
      %Player{id: 1, sport: "mlb", external_id: "100", name: "Hitter", position: "OF"},
      %Player{id: 2, sport: "mlb", external_id: "200", name: "Ace", position: "SP"},
      %Player{id: 3, sport: "mlb", external_id: "300", name: "DNP", position: "C"},
      %Player{id: 4, sport: "mlb", external_id: "not-seeded", name: "Slug Id", position: "1B"}
    ]
  end

  describe "stats_final?/1" do
    test "true when every in-window game is FINAL" do
      Process.put({:scoreboard, "20260628"}, {:ok, %{"events" => [event("501", "STATUS_FINAL")]}})
      assert MlbEspn.stats_final?(window())
    end

    test "false when a game is not final (defer)" do
      Process.put({:scoreboard, "20260628"}, {:ok, %{"events" => [event("501", "STATUS_IN_PROGRESS")]}})
      refute MlbEspn.stats_final?(window())
    end

    test "true for a zero-game window" do
      Process.put({:scoreboard, "20260628"}, {:ok, %{"events" => []}})
      assert MlbEspn.stats_final?(window())
    end

    test "false when the scoreboard can't be fetched" do
      Process.put({:scoreboard, "20260628"}, {:error, {:transport, :timeout}})
      refute MlbEspn.stats_final?(window())
    end
  end

  describe "fetch_stats/2" do
    test "sums each player's in-window gamelog into full mlb categories; zeros DNP + non-seeded" do
      Process.put({:scoreboard, "20260628"}, {:ok, %{"events" => [event("501", "STATUS_FINAL")]}})

      # Hitter: 501 counts; 777 is out of window and must be ignored.
      Process.put(
        {:gamelog, "100"},
        batting_log([
          # AB R H 2B 3B HR RBI BB HBP SO SB
          {"501", ~w(4 1 2 1 0 1 3 1 0 1 1)},
          {"777", ~w(5 5 5 5 5 5 5 5 5 5 5)}
        ])
      )

      # Pitcher: 6.0 IP, 7 K, 2 ER, win.
      Process.put(
        {:gamelog, "200"},
        # innings H R ER HR BB K wins-losses
        pitching_log([{"501", ["6.0", "4", "2", "2", "1", "1", "7", "W(5-2)"]}])
      )

      # DNP: a gamelog with only an out-of-window game.
      Process.put({:gamelog, "300"}, batting_log([{"777", ~w(4 1 1 0 0 0 0 0 0 1 0)}]))

      stats = MlbEspn.fetch_stats(players(), window())

      assert stats[1] == %{
               "single" => 0,
               "double" => 1,
               "triple" => 0,
               "home_run" => 1,
               "rbi" => 3,
               "run" => 1,
               "walk" => 1,
               "stolen_base" => 1,
               "inning_pitched" => 0,
               "strikeout_pitched" => 0,
               "win" => 0,
               "earned_run" => 0
             }

      assert stats[2]["inning_pitched"] == 6.0
      assert stats[2]["strikeout_pitched"] == 7
      assert stats[2]["earned_run"] == 2
      assert stats[2]["win"] == 1
      assert stats[2]["home_run"] == 0

      zero = Map.new(~w(single double triple home_run rbi run walk stolen_base inning_pitched strikeout_pitched win earned_run), &{&1, 0})
      assert stats[3] == zero
      assert stats[4] == zero
      assert Map.keys(stats) |> Enum.sort() == [1, 2, 3, 4]
    end
  end
end
