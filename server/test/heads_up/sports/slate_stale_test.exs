defmodule HeadsUp.Sports.SlateStaleTest do
  # async: false — drives the shared persistent_term slate cache.
  use ExUnit.Case, async: false

  alias HeadsUp.Sports.Slate

  defmodule StubClient do
    def scoreboard(_sport, _range, _opts \\ []) do
      Process.get(:slate_events, {:ok, %{"events" => []}})
    end
  end

  setup do
    # The cache is keyed by {Slate, sport, first ET day}; clear it so each test
    # starts cold.
    :persistent_term.erase({Slate, "wnba", Slate.today()})
    on_exit(fn -> :persistent_term.erase({Slate, "wnba", Slate.today()}) end)
    :ok
  end

  defp event(iso, teams, state \\ "pre") do
    %{
      "date" => iso,
      "status" => %{"type" => %{"state" => state}},
      "competitions" => [%{"competitors" => Enum.map(teams, &%{"team" => %{"abbreviation" => &1}})}]
    }
  end

  defp iso_at(date), do: "#{Date.to_iso8601(date)}T23:00Z"

  defp warm_cache_with(events) do
    Process.put(:slate_events, {:ok, %{"events" => events}})
    {:ok, _} = Slate.upcoming("wnba", client: StubClient, cache: true)
  end

  defp feed_down, do: Process.put(:slate_events, {:error, {:transport, :timeout}})

  test "a good answer is served from cache" do
    tomorrow = Date.add(Slate.today(), 1)
    warm_cache_with([event(iso_at(tomorrow), ["LV", "NY"])])

    assert {:ok, days} = Slate.upcoming("wnba", client: StubClient, cache: true)
    day = Enum.find(days, &(&1.date == tomorrow))
    assert day.games == 1
  end

  test "an outage serves the last good schedule instead of an error" do
    tomorrow = Date.add(Slate.today(), 1)
    warm_cache_with([event(iso_at(tomorrow), ["LV", "NY"])])

    feed_down()

    # Without stale-serving this is {:error, ...} and the slate picker empties
    # out — which is exactly what happened when ESPN started refusing us.
    assert {:ok, days} = Slate.upcoming("wnba", client: StubClient, cache: true)
    day = Enum.find(days, &(&1.date == tomorrow))
    assert day.games == 1
    assert day.upcoming == 1
  end

  test "a stale 'not started yet' does not survive its own kickoff" do
    # Cached while the game was upcoming; by the time we serve it stale, that
    # day is in the past. Serving "pre" would offer a team whose game is over —
    # the hindsight exploit the slate exists to prevent.
    yesterday = Date.add(Slate.today(), -1)
    warm_cache_with([event(iso_at(yesterday), ["LV", "NY"])])

    feed_down()

    assert {:ok, days} = Slate.upcoming("wnba", client: StubClient, cache: true)
    # Past days aren't in the upcoming window at all, so the guarantee that
    # matters is simply that nothing from a finished day is offered.
    refute Enum.any?(days, fn d -> d.date == yesterday and d.upcoming > 0 end)
  end

  test "with nothing cached, an outage still reports the error" do
    feed_down()
    assert {:error, _} = Slate.upcoming("wnba", client: StubClient, cache: true)
  end
end
