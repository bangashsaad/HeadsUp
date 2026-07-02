defmodule HeadsUp.Drafts.PoolFilter do
  @moduledoc """
  Keeps the draft board honest about TODAY's games: the scoring window only
  opens when the draft completes, so a player whose game already tipped off
  scores 0 for it — drafting them is a silently wasted pick.

  `teams_already_started/2` returns the team abbrevs whose slate today (ET) has
  fully started — a team with a game still in the "pre" state stays draftable
  (doubleheader-safe: an MLB team that already played game 1 but has game 2
  upcoming is NOT excluded).

  Fails OPEN (empty set → no exclusions) when the sport has no live feed or the
  scoreboard is unreachable: a complete board beats a broken draft. The caller
  applies its own fail-open guard against gutting the pool entirely.
  """
  alias HeadsUp.Sports.Espn.Client

  @et_offset_seconds -4 * 3600

  @doc "Team abbrevs whose games today (ET) have ALL started. `opts[:client]`/`opts[:now]` for tests."
  @spec teams_already_started(String.t(), keyword()) :: MapSet.t(String.t())
  def teams_already_started(sport, opts \\ []) do
    client = Keyword.get(opts, :client, Client)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with true <- Client.supported?(sport),
         {:ok, body} <- client.scoreboard(sport, et_ymd(now)) do
      body |> Map.get("events", []) |> List.wrap() |> started_teams()
    else
      _ -> MapSet.new()
    end
  end

  defp started_teams(events) do
    events
    |> Enum.flat_map(fn e ->
      state = get_in(e, ["status", "type", "state"])

      e
      |> get_in(["competitions", Access.at(0), "competitors"])
      |> List.wrap()
      |> Enum.map(fn c -> {get_in(c, ["team", "abbreviation"]), state} end)
    end)
    |> Enum.reject(fn {abbrev, _state} -> is_nil(abbrev) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.filter(fn {_abbrev, states} -> "pre" not in states end)
    |> MapSet.new(fn {abbrev, _states} -> abbrev end)
  end

  defp et_ymd(now) do
    now
    |> DateTime.add(@et_offset_seconds, :second)
    |> DateTime.to_date()
    |> Calendar.strftime("%Y%m%d")
  end
end
