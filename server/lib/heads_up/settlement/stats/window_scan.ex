defmodule HeadsUp.Settlement.Stats.WindowScan do
  @moduledoc """
  Shared scoring-window → ESPN scoreboard scan for the live stats providers.
  Enumerates the ET calendar days a `Window` touches, pulls each day's
  scoreboard via the injected `client`, and returns the events whose tip-off /
  first-pitch falls inside `[opens_at, closes_at]` as `%{id, final?}`.

  Pure aside from the `client.scoreboard/2` calls, so both the basketball
  (boxscore) and baseball (gamelog) providers agree on which games count and
  when a window is final. Returns `{:ok, events}` or `{:error, reason}` (any
  day's scoreboard unreachable → the caller must defer, since finality is
  unprovable).
  """
  alias HeadsUp.Settlement.Window

  # The live WNBA/MLB seasons are EDT = UTC−4; no tzdata needed.
  @et_offset_seconds -4 * 3600
  # Upper bound so a mis-built months-long window can't hammer ESPN.
  @max_days 35

  @doc "In-window events as `[%{id, final?, state}]`, or `{:error, reason}`. `state` is ESPN's \"pre\"|\"in\"|\"post\"."
  @spec events(module(), Window.t()) ::
          {:ok, [%{id: String.t(), final?: boolean(), state: String.t() | nil}]} | {:error, term()}
  def events(client, %Window{sport: sport, opens_at: o, closes_at: c}) do
    case et_dates(o, c) do
      {:error, reason} ->
        {:error, reason}

      {:ok, dates} ->
        Enum.reduce_while(dates, {:ok, []}, fn date, {:ok, acc} ->
          ymd = Calendar.strftime(date, "%Y%m%d")

          case client.scoreboard(sport, ymd) do
            {:ok, body} -> {:cont, {:ok, acc ++ parse_events(body, o, c)}}
            {:error, reason} -> {:halt, {:error, {:scoreboard, ymd, reason}}}
          end
        end)
    end
  end

  defp parse_events(body, opens_at, closes_at) do
    body
    |> Map.get("events", [])
    |> List.wrap()
    |> Enum.filter(fn e -> in_window?(e["date"], opens_at, closes_at) end)
    |> Enum.map(fn e ->
      %{
        id: to_string(e["id"]),
        final?: get_in(e, ["status", "type", "name"]) == "STATUS_FINAL",
        state: get_in(e, ["status", "type", "state"])
      }
    end)
  end

  @doc "Count in-window games by state (`%{final, live, upcoming}`); on feed error, all zero."
  @spec game_counts(module(), Window.t()) :: %{final: non_neg_integer(), live: non_neg_integer(), upcoming: non_neg_integer()}
  def game_counts(client, window) do
    case events(client, window) do
      {:ok, evs} ->
        %{
          final: Enum.count(evs, & &1.final?),
          live: Enum.count(evs, &(&1.state == "in")),
          upcoming: Enum.count(evs, &(&1.state == "pre"))
        }

      {:error, _} ->
        %{final: 0, live: 0, upcoming: 0}
    end
  end

  defp et_dates(o, c) do
    start_d = o |> DateTime.add(@et_offset_seconds, :second) |> DateTime.to_date()
    end_d = c |> DateTime.add(@et_offset_seconds, :second) |> DateTime.to_date()
    span = Date.diff(end_d, start_d)

    cond do
      span < 0 -> {:ok, []}
      span > @max_days -> {:error, {:window_too_wide, span}}
      true -> {:ok, Enum.map(0..span, &Date.add(start_d, &1))}
    end
  end

  defp in_window?(iso, opens_at, closes_at) do
    case parse_dt(iso) do
      {:ok, dt} ->
        DateTime.compare(dt, opens_at) != :lt and DateTime.compare(dt, closes_at) != :gt

      :error ->
        false
    end
  end

  # ESPN emits "2026-06-30T23:00Z" (no seconds) as well as full ISO8601.
  defp parse_dt(iso) when is_binary(iso) do
    fixed = Regex.replace(~r/T(\d{2}):(\d{2})Z$/, iso, "T\\1:\\2:00Z")

    case DateTime.from_iso8601(fixed) do
      {:ok, dt, _} -> {:ok, dt}
      _ -> :error
    end
  end

  defp parse_dt(_), do: :error
end
