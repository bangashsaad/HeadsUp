defmodule HeadsUp.Sports.PoolRefresher do
  @moduledoc """
  Weekly roster refresh for every in-season sport, with pruning: cuts,
  retirements and call-ups stop being a calendar item somebody has to
  remember. Runs Wednesdays once it's past 6am ET — NFL cut-down day is a
  Tuesday, so the pool is clean before the week's slates open — and
  otherwise ticks hourly doing nothing.

  `refresh/1` is public so a human can run it off-schedule:

      /app/bin/heads_up rpc 'HeadsUp.Sports.PoolRefresher.refresh("nfl")'

  Projections (the FPPG pass) are NOT recomputed here — that's one ESPN
  request per player and belongs to the manual `mix heads_up.seed_sport`.
  """
  use GenServer

  require Logger

  alias HeadsUp.Sports.{Season, Seeds}
  alias HeadsUp.Sports.Espn.Client

  @tick_ms :timer.hours(1)
  # First tick soon after boot (a machine that sleeps a lot still gets its
  # Wednesday), but not so soon it races the DB pool warming up.
  @first_tick_ms :timer.minutes(5)
  @refresh_iso_weekday 3
  @refresh_hour_et 6
  # The rest of the app's ET convention (Slate/Contests): fixed UTC-4. An
  # hour of drift in November is irrelevant to a once-a-week job.
  @et_offset_s -4 * 3600

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    tick_ms = Keyword.get(opts, :tick_ms, @tick_ms)
    Process.send_after(self(), :tick, Keyword.get(opts, :first_tick_ms, @first_tick_ms))
    {:ok, %{tick_ms: tick_ms, ran_on: %{}}}
  end

  @impl true
  def handle_info(:tick, state) do
    HeadsUp.Heartbeat.record(:pool_refresher)
    now = DateTime.utc_now()

    ran_on =
      Enum.reduce(Client.leagues(), state.ran_on, fn sport, acc ->
        if due?(sport, Map.get(acc, sport), now) and Season.in_season?(sport) do
          refresh(sport)
          Map.put(acc, sport, et_date(now))
        else
          acc
        end
      end)

    Process.send_after(self(), :tick, state.tick_ms)
    {:noreply, %{state | ran_on: ran_on}}
  end

  @doc """
  Pure schedule rule: Wednesday, 6am ET or later, and not already run today.
  `last_ran` is the ET date of the last run on this node (nil = never).
  """
  def due?(_sport, last_ran, now \\ DateTime.utc_now()) do
    et = DateTime.add(now, @et_offset_s, :second)
    Date.day_of_week(et) == @refresh_iso_weekday and et.hour >= @refresh_hour_et and last_ran != DateTime.to_date(et)
  end

  @doc "Refresh one sport's roster from ESPN and prune what the feed dropped. Logs the outcome."
  def refresh(sport) do
    case Seeds.run_from_espn(sport, prune: true) do
      {:ok, %{prune_skipped: why} = s} ->
        Logger.warning("pool refresh #{sport}: #{s.updated} matched, #{s.inserted} new — prune SKIPPED (#{inspect(why)})")
        {:ok, s}

      {:ok, s} ->
        Logger.info(
          "pool refresh #{sport}: #{s.updated} matched, #{s.inserted} new, #{Map.get(s, :deleted, 0)} deleted, #{Map.get(s, :retired, 0)} retired to FA"
        )

        {:ok, s}

      {:error, reason} ->
        Logger.error("pool refresh #{sport} failed (nothing written): #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp et_date(now), do: now |> DateTime.add(@et_offset_s, :second) |> DateTime.to_date()
end
