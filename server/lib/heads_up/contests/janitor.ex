defmodule HeadsUp.Contests.Janitor do
  @moduledoc """
  Hourly sweep for duels that died on the vine — pending challenges nobody
  answered and lobbies nobody drafted in, both `@cutoff_hours` past their draft
  time. Matters more now that coins are real: every stuck duel is somebody's
  stake locked in escrow. The queries + refunds live in
  `Contests.expire_stale/1`; this process is just the clock.

  The FIRST sweep runs shortly after boot rather than a full interval in.
  Production scales to zero: the machine wakes for a request, serves it, and is
  stopped again long before an hour is up, so an hour-delayed first tick never
  fired at all — the janitor sat dead for weeks while stale duels piled up.
  Anything that must actually happen on a scale-to-zero node has to happen
  near boot. The test env keeps both delays huge so the sweep stays silent.
  """
  use GenServer

  require Logger

  @cutoff_hours 24

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    interval =
      Keyword.get(opts, :interval_ms, Application.get_env(:heads_up, :janitor_interval_ms, :timer.hours(1)))

    first =
      Keyword.get(
        opts,
        :first_sweep_ms,
        Application.get_env(:heads_up, :janitor_first_sweep_ms, :timer.seconds(45))
      )

    # Late enough that a booting node serves requests first, early enough that
    # a machine which is only awake for a few minutes still gets swept.
    Process.send_after(self(), :sweep, first)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:sweep, state) do
    HeadsUp.Heartbeat.record(:janitor)

    case HeadsUp.Contests.expire_stale(@cutoff_hours) do
      %{pending: 0, lobby: 0} -> :ok
      counts -> Logger.info("Janitor expired stale duels: #{inspect(counts)}")
    end

    case HeadsUp.Accounts.prune_expired_tokens() do
      0 -> :ok
      n -> Logger.info("Janitor pruned #{n} expired login tokens")
    end

    # The money invariant, re-derived hourly. Integrity.run/0 logs and
    # remembers; /api/health turns a bad verdict into a 503.
    HeadsUp.Coins.Integrity.run()

    Process.send_after(self(), :sweep, state.interval)
    {:noreply, state}
  end
end
