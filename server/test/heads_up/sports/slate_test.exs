defmodule HeadsUp.Sports.SlateTest do
  use ExUnit.Case, async: true

  alias HeadsUp.Sports.Slate

  # Injected via opts[:client] — bypasses both the real feed and the cache.
  defmodule StubClient do
    def scoreboard(_sport, range, _extra \\ []) do
      send(self(), {:scoreboard_range, range})
      Process.get(:slate_events, {:ok, %{"events" => []}})
    end
  end

  # 2026-07-13 12:00 ET expressed in UTC.
  @now ~U[2026-07-13 16:00:00Z]

  defp event(iso_date, teams, state \\ "pre") do
    %{
      "date" => iso_date,
      "status" => %{"type" => %{"state" => state}},
      "competitions" => [
        %{"competitors" => Enum.map(teams, &%{"team" => %{"abbreviation" => &1}})}
      ]
    }
  end

  test "upcoming/2 groups games into ET days with team lists, zero-game days included" do
    Process.put(
      :slate_events,
      {:ok,
       %{
         "events" => [
           # 7pm ET tonight …
           event("2026-07-13T23:00Z", ["LV", "NY"]),
           # … and a cross-midnight-UTC tip that is STILL July 13 in ET (8:30pm).
           event("2026-07-14T00:30Z", ["SEA", "LA"]),
           # one game two days out
           event("2026-07-15T23:00Z", ["MIN", "CON"])
         ]
       }}
    )

    assert {:ok, days} = Slate.upcoming("wnba", client: StubClient, now: @now)
    assert length(days) == 8

    # One range call covered the whole horizon.
    assert_received {:scoreboard_range, "20260713-20260720"}

    today = Enum.find(days, &(&1.date == ~D[2026-07-13]))
    assert today.games == 2
    assert Enum.sort(today.teams) == ["LA", "LV", "NY", "SEA"]

    assert %{games: 0, teams: []} = Enum.find(days, &(&1.date == ~D[2026-07-14]))
    assert %{games: 1} = Enum.find(days, &(&1.date == ~D[2026-07-15]))
  end

  test "on/3 answers one day, and a date outside the horizon is just empty" do
    Process.put(:slate_events, {:ok, %{"events" => [event("2026-07-13T23:00Z", ["LV", "NY"])]}})

    assert {:ok, %{games: 1, teams: teams}} = Slate.on("wnba", ~D[2026-07-13], client: StubClient, now: @now)
    assert Enum.sort(teams) == ["LV", "NY"]

    assert {:ok, %{games: 0, teams: []}} = Slate.on("wnba", ~D[2026-09-01], client: StubClient, now: @now)
  end

  test "upcoming counts only games that haven't tipped" do
    Process.put(
      :slate_events,
      {:ok,
       %{
         "events" => [
           event("2026-07-13T21:00Z", ["LV", "NY"], "post"),
           event("2026-07-13T23:00Z", ["SEA", "LA"], "in"),
           event("2026-07-14T01:00Z", ["MIN", "CON"], "pre")
         ]
       }}
    )

    assert {:ok, days} = Slate.upcoming("wnba", client: StubClient, now: @now)
    today = Enum.find(days, &(&1.date == ~D[2026-07-13]))

    assert today.games == 3
    assert today.upcoming == 1
    assert today.upcoming_teams == ["MIN", "CON"]
  end

  test "a feed error propagates so callers can fail open" do
    Process.put(:slate_events, {:error, {:transport, :timeout}})
    assert {:error, _} = Slate.upcoming("wnba", client: StubClient, now: @now)
  end

  test "an unsupported sport is an error, not a crash" do
    assert {:error, :unsupported_sport} = Slate.upcoming("curling", client: StubClient, now: @now)
  end
end
