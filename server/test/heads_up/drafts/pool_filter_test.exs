defmodule HeadsUp.Drafts.PoolFilterTest do
  use ExUnit.Case, async: true

  alias HeadsUp.Drafts.PoolFilter

  defmodule StubClient do
    def scoreboard(_sport, _ymd) do
      {:ok,
       %{
         "events" => [
           game("post", "LV", "NY"),
           game("in", "MIN", "PHX"),
           game("pre", "SEA", "ATL"),
           # doubleheader: CHI already played but has another game upcoming
           game("post", "CHI", "IND"),
           game("pre", "CHI", "IND")
         ]
       }}
    end

    defp game(state, away, home) do
      %{
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

  test "excludes teams whose games all started; keeps pre-game and doubleheader teams" do
    started = PoolFilter.teams_already_started("wnba", client: StubClient)

    assert MapSet.member?(started, "LV") and MapSet.member?(started, "NY")
    assert MapSet.member?(started, "MIN") and MapSet.member?(started, "PHX")
    # game hasn't started
    refute MapSet.member?(started, "SEA")
    refute MapSet.member?(started, "ATL")
    # doubleheader: still has an upcoming game today
    refute MapSet.member?(started, "CHI")
    refute MapSet.member?(started, "IND")
  end

  test "fails open (empty set) when the scoreboard is unreachable" do
    assert PoolFilter.teams_already_started("wnba", client: ErrClient) == MapSet.new()
  end

  test "fails open for a sport without a live feed" do
    assert PoolFilter.teams_already_started("cricket", client: StubClient) == MapSet.new()
  end
end
