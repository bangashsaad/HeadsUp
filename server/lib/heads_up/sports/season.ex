defmodule HeadsUp.Sports.Season do
  @moduledoc """
  Is a sport playable RIGHT NOW? Playable = ESPN shows a real game within the
  next `window_days` (default 10) AND the sport has a real (ESPN-seeded)
  player pool. Off-season sports can't be challenged — an NBA duel in July
  would draft into an empty board and never score.

  One scoreboard call per sport (ESPN accepts a YYYYMMDD-YYYYMMDD range),
  cached for an hour. The schedule probe FAILS OPEN on feed errors — an ESPN
  hiccup must never lock the whole app — so the hard gate is specifically
  "ESPN answered and said: no games in the window".
  """
  import Ecto.Query, warn: false

  alias HeadsUp.Repo
  alias HeadsUp.Sports.Espn.Client
  alias HeadsUp.Sports.Player

  @sports ~w(wnba mlb nba nfl)
  @et_offset_seconds -4 * 3600
  @ttl_ms 60 * 60 * 1000
  # A pool is real when at least this many ESPN-seeded (numeric-id) players exist.
  @min_pool 30

  def window_days, do: Application.get_env(:heads_up, :playable_window_days, 10)

  @doc "Every supported sport with its playability. Drives the challenge form."
  def statuses(opts \\ []), do: Enum.map(@sports, &status(&1, opts))

  @doc "One sport's playability: schedule window + pool readiness."
  def status(sport, opts \\ []) do
    probe = games_in_window(sport, opts)

    games_ok =
      case probe do
        {:ok, nil} -> false
        {:ok, _first} -> true
        :error -> true
      end

    pool_ready = real_pool_count(sport) >= @min_pool

    %{
      sport: sport,
      playable: games_ok and pool_ready,
      next_game_at: with({:ok, first} <- probe, do: first),
      pool_ready: pool_ready
    }
  end

  @doc """
  The challenge-creation backstop: false ONLY when ESPN positively reported an
  empty window. Pool readiness is left to the UI gate (and the draft's own
  fail-open pool filter) so infra-less test envs keep working.
  """
  def in_season?(sport, opts \\ []) do
    case games_in_window(sport, opts) do
      {:ok, nil} -> false
      _ -> true
    end
  end

  # --- probe + cache --------------------------------------------------------

  defp games_in_window(sport, opts) do
    client = Keyword.get(opts, :client, default_client())
    now = Keyword.get(opts, :now, DateTime.utc_now())
    key = {__MODULE__, sport}

    if Keyword.get(opts, :cache, true) do
      case cached(key) do
        {:hit, result} -> result
        :miss -> tap_cache(key, probe(sport, client, now))
      end
    else
      probe(sport, client, now)
    end
  end

  defp cached(key) do
    case :persistent_term.get(key, nil) do
      {ts, result} ->
        if System.monotonic_time(:millisecond) - ts < @ttl_ms, do: {:hit, result}, else: :miss

      nil ->
        :miss
    end
  end

  defp tap_cache(key, result) do
    :persistent_term.put(key, {System.monotonic_time(:millisecond), result})
    result
  end

  defp probe(sport, client, now) do
    if Client.supported?(sport) do
      start = now |> DateTime.add(@et_offset_seconds, :second) |> DateTime.to_date()
      range = "#{ymd(start)}-#{ymd(Date.add(start, window_days()))}"

      case client.scoreboard(sport, range) do
        {:ok, body} ->
          first =
            body
            |> Map.get("events", [])
            |> Enum.map(& &1["date"])
            |> Enum.reject(&is_nil/1)
            |> Enum.min(fn -> nil end)

          {:ok, first}

        {:error, _} ->
          :error
      end
    else
      # No league mapping = nothing to verify against; fail open.
      :error
    end
  end

  defp ymd(date), do: Calendar.strftime(date, "%Y%m%d")

  defp real_pool_count(sport) do
    Repo.one(
      from p in Player,
        where: p.sport == ^sport and fragment("? ~ '^[0-9]+$'", p.external_id),
        select: count(p.id)
    ) || 0
  end

  defp default_client, do: Application.get_env(:heads_up, :season_client, Client)
end
