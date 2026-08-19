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

  describe "probable pitchers" do
    defmodule ProbablesStub do
      def scoreboard(_sport, "20260701") do
        {:ok,
         %{
           "events" => [
             %{
               "date" => "2026-07-02T00:00Z",
               "status" => %{"type" => %{"state" => "pre"}},
               "competitions" => [
                 %{
                   "competitors" => [
                     %{"team" => %{"abbreviation" => "ATL"}, "probables" => [%{"athlete" => %{"id" => 30948}}]},
                     %{"team" => %{"abbreviation" => "NYM"}, "probables" => [%{"athlete" => %{"id" => "39832"}}]}
                   ]
                 }
               ]
             },
             # A game already running publishes probables too — they must NOT
             # count (that pitcher is mid-start; drafting him is hindsight).
             %{
               "date" => "2026-07-01T17:00Z",
               "status" => %{"type" => %{"state" => "in"}},
               "competitions" => [
                 %{"competitors" => [%{"team" => %{"abbreviation" => "LAD"}, "probables" => [%{"athlete" => %{"id" => "1111"}}]}]}
               ]
             }
           ]
         }}
      end

      def scoreboard(_sport, _ymd), do: {:ok, %{"events" => []}}
    end

    test "scan collects probable starters from not-yet-started games only" do
      %{ok: true, probable_ids: probables} = PoolFilter.scan("mlb", client: ProbablesStub, now: @now)
      assert MapSet.member?(probables, "30948")
      assert MapSet.member?(probables, "39832")
      refute MapSet.member?(probables, "1111")
    end

    test "draftable?: pitchers need to be probable; hitters ride the team schedule" do
      next = %{"ATL" => "2026-07-02T00:00Z", "NYM" => "2026-07-02T00:00Z"}
      probables = MapSet.new(["30948"])

      sale = %{position: "SP", team: "ATL", external_id: "30948"}
      off_day_sp = %{position: "SP", team: "NYM", external_id: "99999"}
      reliever = %{position: "RP", team: "ATL", external_id: "88888"}
      hitter = %{position: "1B", team: "ATL", external_id: "77777"}
      idle_hitter = %{position: "OF", team: "STL", external_id: "66666"}

      assert PoolFilter.draftable?(sale, "mlb", next, probables)
      refute PoolFilter.draftable?(off_day_sp, "mlb", next, probables)
      refute PoolFilter.draftable?(reliever, "mlb", next, probables)
      assert PoolFilter.draftable?(hitter, "mlb", next, probables)
      refute PoolFilter.draftable?(idle_hitter, "mlb", next, probables)

      # No probables published (early scan / feed gap): pitchers pass on the
      # team schedule rather than gutting the P slot.
      assert PoolFilter.draftable?(off_day_sp, "mlb", next, MapSet.new())

      # A probable whose game already started has left the schedule map.
      refute PoolFilter.draftable?(%{sale | team: "LAD"}, "mlb", next, probables)

      # Other sports never consult probables.
      guard = %{position: "G", team: "ATL", external_id: "55555"}
      assert PoolFilter.draftable?(guard, "wnba", next, probables)
    end
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
