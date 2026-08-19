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

  `scan/2` returns `%{ok: bool, next_game_at: %{team_abbrev => iso_utc},
  preseason: bool}` — each team's earliest "pre"-state game across the two days,
  plus whether those games are exhibition. `ok: false` means the feed couldn't be
  read (or the sport has no live feed): callers must fail OPEN (a complete board
  beats a broken draft).
  """
  alias HeadsUp.Sports.Espn.Client

  @et_offset_seconds -4 * 3600

  @doc """
  Scan today + tomorrow (ET) by default, or exactly `opts[:dates]` — a
  slate-scoped duel passes its slate day so only THAT day's not-yet-started
  games count. `opts[:client]`/`opts[:now]` for tests.
  """
  @spec scan(String.t(), keyword()) :: %{ok: boolean(), next_game_at: %{String.t() => String.t()}}
  def scan(sport, opts \\ []) do
    client = Keyword.get(opts, :client, Client)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    if Client.supported?(sport) do
      today = now |> DateTime.add(@et_offset_seconds, :second) |> DateTime.to_date()

      (Keyword.get(opts, :dates) || [today, Date.add(today, 1)])
      |> Enum.reduce_while({:ok, []}, fn date, {:ok, acc} ->
        case client.scoreboard(sport, Calendar.strftime(date, "%Y%m%d")) do
          {:ok, body} -> {:cont, {:ok, acc ++ (body |> Map.get("events", []) |> List.wrap())}}
          {:error, _} -> {:halt, :error}
        end
      end)
      |> case do
        {:ok, events} ->
          %{
            ok: true,
            next_game_at: next_games(events),
            preseason: preseason?(events),
            probable_ids: probable_ids(events)
          }

        :error ->
          %{ok: false, next_game_at: %{}, preseason: false, probable_ids: MapSet.new()}
      end
    else
      %{ok: false, next_game_at: %{}, preseason: false, probable_ids: MapSet.new()}
    end
  end

  @doc """
  Whether a pool player belongs on the board. Hitters (and every non-baseball
  player) draft off the team schedule; baseball pitchers only when they're a
  LISTED probable starter whose game hasn't begun — a team playing tonight
  says nothing about whether its ace throws (a real duel drafted Chris Sale on
  his off day and he scored an honest zero). Relievers never appear in
  probables, so they leave the board with the off-day starters — the
  DFS-standard rule. If ESPN publishes no probables at all for the slate
  (early scan, feed gap), every pitcher passes rather than gutting the P slot.
  """
  def draftable?(player, "mlb", next_game_at, probables) do
    if player.position in ["SP", "RP"] and MapSet.size(probables) > 0 do
      MapSet.member?(probables, player.external_id) and Map.has_key?(next_game_at, player.team)
    else
      Map.has_key?(next_game_at, player.team)
    end
  end

  def draftable?(player, _sport, next_game_at, _probables), do: Map.has_key?(next_game_at, player.team)

  # The listed probable starters across the scanned slate, as ESPN athlete ids.
  # Baseball's board uses this to offer only pitchers who actually take the
  # mound: a team playing tonight says nothing about whether its ace throws.
  defp probable_ids(events) do
    events
    |> Enum.filter(fn e -> get_in(e, ["status", "type", "state"]) == "pre" end)
    |> Enum.flat_map(fn e -> e |> get_in(["competitions", Access.at(0), "competitors"]) |> List.wrap() end)
    |> Enum.flat_map(fn c -> List.wrap(c["probables"]) end)
    |> Enum.map(fn p -> get_in(p, ["athlete", "id"]) end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new(&to_string/1)
  end

  # ESPN season types: 1 = preseason, 2 = regular, 3 = post. Football exhibition
  # games are the case that matters — starters play a series or two, so a board
  # ranked by last season's per-game average is actively misleading. The draft
  # room says so out loud rather than letting people find out by drafting a
  # starter who takes three snaps.
  defp preseason?(events) do
    events != [] and Enum.all?(events, &(get_in(&1, ["season", "type"]) == 1))
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
