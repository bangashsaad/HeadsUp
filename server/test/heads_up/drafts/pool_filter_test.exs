defmodule HeadsUp.Drafts.PoolFilterTest do
  use ExUnit.Case, async: true

  alias HeadsUp.Drafts.PoolFilter

  # 2026-07-01 16:00 ET → scans "20260701" (today) + "20260702" (tomorrow).
  @now ~U[2026-07-01 20:00:00Z]

  defmodule StubClient do
    def scoreboard(_sport, "20260701") do
      {:ok,
       %{
         "events" => [
           game("post", "2026-07-01T17:00Z", "NY", "WSH"),
           game("in", "2026-07-01T23:00Z", "MIN", "PHX"),
           game("pre", "2026-07-02T00:00Z", "SEA", "ATL"),
           # doubleheader: CHI/IND already played game 1, game 2 upcoming
           game("post", "2026-07-01T17:00Z", "CHI", "IND"),
           game("pre", "2026-07-01T23:30Z", "CHI", "IND")
         ]
       }}
    end

    def scoreboard(_sport, "20260702") do
      # LV played earlier today? No — LV only plays tomorrow.
      {:ok, %{"events" => [game("pre", "2026-07-02T23:00Z", "LV", "DAL")]}}
    end

    defp game(state, date, away, home) do
      %{
        "date" => date,
        "status" => %{"type" => %{"state" => state}},
        "competitions" => [
          %{"competitors" => [%{"team" => %{"abbreviation" => away}}, %{"team" => %{"abbreviation" => home}}]}
        ]
      }
    end
  end

  defmodule ErrClient do
    def scoreboard(_sport, _ymd), do: {:error, {:transport, :timeout}}
  end

  test "maps each team to its next not-yet-started game across today + tomorrow" do
    %{ok: true, next_game_at: next} = PoolFilter.scan("wnba", client: StubClient, now: @now)

    # upcoming tonight
    assert next["SEA"] == "2026-07-02T00:00Z"
    assert next["ATL"] == "2026-07-02T00:00Z"
    # doubleheader: game 1 done, game 2 is the next game
    assert next["CHI"] == "2026-07-01T23:30Z"
    assert next["IND"] == "2026-07-01T23:30Z"
    # only playing tomorrow
    assert next["LV"] == "2026-07-02T23:00Z"
    assert next["DAL"] == "2026-07-02T23:00Z"
    # already played / in progress, nothing else scheduled → no next game
    refute Map.has_key?(next, "NY")
    refute Map.has_key?(next, "WSH")
    refute Map.has_key?(next, "MIN")
    refute Map.has_key?(next, "PHX")
  end

  test "reports ok: false when the scoreboard is unreachable (caller fails open)" do
    assert %{ok: false, next_game_at: %{}} = PoolFilter.scan("wnba", client: ErrClient, now: @now)
  end

  test "reports ok: false for a sport without a live feed" do
    assert %{ok: false, next_game_at: %{}} = PoolFilter.scan("cricket", client: StubClient, now: @now)
  end

  describe "preseason detection" do
    defmodule PreStub do
      def scoreboard(_sport, _ymd) do
        {:ok,
         %{
           "events" => [
             %{
               "date" => "2026-08-07T00:00Z",
               "season" => %{"type" => 1, "slug" => "preseason"},
               "status" => %{"type" => %{"state" => "pre"}},
               "competitions" => [
                 %{"competitors" => [%{"team" => %{"abbreviation" => "ARI"}}, %{"team" => %{"abbreviation" => "CAR"}}]}
               ]
             }
           ]
         }}
      end
    end

    defmodule RegularStub do
      def scoreboard(_sport, _ymd) do
        {:ok,
         %{
           "events" => [
             %{
               "date" => "2026-09-13T17:00Z",
               "season" => %{"type" => 2, "slug" => "regular-season"},
               "status" => %{"type" => %{"state" => "pre"}},
               "competitions" => [
                 %{"competitors" => [%{"team" => %{"abbreviation" => "KC"}}]}
               ]
             }
           ]
         }}
      end
    end

    test "flags an exhibition slate" do
      assert %{ok: true, preseason: true} = PoolFilter.scan("nfl", client: PreStub, dates: [~D[2026-08-06]])
    end

    test "a regular-season slate is not flagged" do
      assert %{ok: true, preseason: false} = PoolFilter.scan("nfl", client: RegularStub, dates: [~D[2026-09-13]])
    end

    test "an unreadable feed is never reported as preseason" do
      assert %{ok: false, preseason: false} = PoolFilter.scan("nfl", client: ErrClient, dates: [~D[2026-08-06]])
    end
  end
end
