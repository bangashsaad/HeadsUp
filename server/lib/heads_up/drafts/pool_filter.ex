defmodule HeadsUp.Drafts.PoolFilter do
  @moduledoc """
  Keeps the draft board honest about upcoming games. The scoring window opens
  when the draft COMPLETES and runs ~24h, so what matters for a pick is the
  player's NEXT not-yet-started game across today + tomorrow (ET):

    * a team whose game already tipped off scores 0 for it — but if they play
      again tomorrow (routine in MLB), that game counts, so they stay draftable;
    * a team with no upcoming game in the span can't score at all;
    * every draftable player gets annotated with WHEN they play next, so the
      board can show it during the draft.

  `scan/2` returns `%{ok: bool, next_game_at: %{team_abbrev => iso_utc}}` —
  each team's earliest "pre"-state game across the two days. `ok: false` means
  the feed couldn't be read (or the sport has no live feed): callers must fail
  OPEN (a complete board beats a broken draft).
  """
  alias HeadsUp.Sports.Espn.Client

  @et_offset_seconds -4 * 3600

  @doc "Scan today + tomorrow (ET). `opts[:client]`/`opts[:now]` for tests."
  @spec scan(String.t(), keyword()) :: %{ok: boolean(), next_game_at: %{String.t() => String.t()}}
  def scan(sport, opts \\ []) do
    client = Keyword.get(opts, :client, Client)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    if Client.supported?(sport) do
      today = now |> DateTime.add(@et_offset_seconds, :second) |> DateTime.to_date()

      [today, Date.add(today, 1)]
      |> Enum.reduce_while({:ok, []}, fn date, {:ok, acc} ->
        case client.scoreboard(sport, Calendar.strftime(date, "%Y%m%d")) do
          {:ok, body} -> {:cont, {:ok, acc ++ (body |> Map.get("events", []) |> List.wrap())}}
          {:error, _} -> {:halt, :error}
        end
      end)
      |> case do
        {:ok, events} -> %{ok: true, next_game_at: next_games(events)}
        :error -> %{ok: false, next_game_at: %{}}
      end
    else
      %{ok: false, next_game_at: %{}}
    end
  end

  # Earliest not-yet-started game per team. ESPN dates are same-format ISO8601
  # UTC strings, so lexicographic min == chronological min.
  defp next_games(events) do
    events
    |> Enum.filter(fn e -> get_in(e, ["status", "type", "state"]) == "pre" end)
    |> Enum.flat_map(fn e ->
      date = e["date"]

      e
      |> get_in(["competitions", Access.at(0), "competitors"])
      |> List.wrap()
      |> Enum.map(fn c -> {get_in(c, ["team", "abbreviation"]), date} end)
    end)
    |> Enum.reject(fn {abbrev, date} -> is_nil(abbrev) or is_nil(date) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {abbrev, dates} -> {abbrev, Enum.min(dates)} end)
  end
end
