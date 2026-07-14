defmodule HeadsUp.Contests.Janitor do
  @moduledoc """
  Hourly sweep for duels that died on the vine — pending challenges nobody
  answered and lobbies nobody drafted in, both `@cutoff_hours` past their draft
  time. Matters more now that coins are real: every stuck duel is somebody's
  stake locked in escrow. The queries + refunds live in
  `Contests.expire_stale/1`; this process is just the clock.
  """
  use GenServer

  require Logger

  @cutoff_hours 24

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    interval =
      Keyword.get(opts, :interval_ms, Application.get_env(:heads_up, :janitor_interval_ms, :timer.hours(1)))

    # First sweep waits a FULL interval (mirrors Settlement.Worker) — so the
    # test env's huge janitor_interval_ms really does keep it silent, and a
    # booting prod node serves requests before it cleans.
    Process.send_after(self(), :sweep, interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:sweep, state) do
    case HeadsUp.Contests.expire_stale(@cutoff_hours) do
      %{pending: 0, lobby: 0} -> :ok
      counts -> Logger.info("Janitor expired stale duels: #{inspect(counts)}")
    end

    Process.send_after(self(), :sweep, state.interval)
    {:noreply, state}
  end
end
