defmodule HeadsUp.Sports.InjuriesTest do
  use ExUnit.Case, async: true

  alias HeadsUp.Sports.Injuries

  defmodule StubClient do
    def injuries(_sport), do: Process.get(:inj, {:ok, %{"injuries" => []}})
  end

  defp entry(id, status, opts \\ []) do
    %{
      "status" => status,
      "athlete" => %{
        "displayName" => Keyword.get(opts, :name, "Player"),
        "headshot" => %{"href" => "https://a.espncdn.com/i/headshots/wnba/players/full/#{id}.png"}
      },
      "details" => %{
        "side" => Keyword.get(opts, :side),
        "type" => Keyword.get(opts, :type),
        "returnDate" => Keyword.get(opts, :return)
      }
    }
  end

  defp stub(entries), do: Process.put(:inj, {:ok, %{"injuries" => [%{"injuries" => entries}]}})

  test "keys by the ESPN athlete id pulled out of the headshot URL" do
    stub([entry("4433431", "Out", side: "Right", type: "Leg", return: "2026-08-10")])

    report = Injuries.for_sport("wnba", client: StubClient)

    assert %{"4433431" => %{status: :out, label: "OUT", detail: "Right Leg", return_date: "2026-08-10"}} = report
  end

  test "basketball and baseball wordings both collapse to out" do
    stub([
      entry("1", "Out"),
      entry("2", "10-Day-IL"),
      entry("3", "60-Day-IL"),
      entry("4", "bereavement"),
      entry("5", "Suspension")
    ])

    report = Injuries.for_sport("wnba", client: StubClient)

    assert Enum.all?(Map.values(report), &(&1.status == :out))
    # IL badges keep the duration so "IL-60" still reads as season-ending.
    assert report["2"].label == "IL-10"
    assert report["3"].label == "IL-60"
  end

  test "day-to-day style statuses are questionable, not out" do
    stub([entry("1", "Day-To-Day"), entry("2", "Questionable"), entry("3", "Probable")])

    report = Injuries.for_sport("wnba", client: StubClient)

    assert Enum.all?(Map.values(report), &(&1.status == :questionable))
    assert report["1"].label == "GTD"
  end

  test "an unrecognized status is questionable — a soft warning beats a silent miss" do
    stub([entry("1", "Weather Delay")])
    assert %{"1" => %{status: :questionable}} = Injuries.for_sport("wnba", client: StubClient)
  end

  test "entries with no resolvable athlete id are skipped, not crashed on" do
    stub([%{"status" => "Out", "athlete" => %{"displayName" => "Ghost"}}])
    assert Injuries.for_sport("wnba", client: StubClient) == %{}
  end

  test "a dead feed fails OPEN so the board still drafts" do
    Process.put(:inj, {:error, :timeout})
    assert Injuries.for_sport("wnba", client: StubClient) == %{}
  end
end
