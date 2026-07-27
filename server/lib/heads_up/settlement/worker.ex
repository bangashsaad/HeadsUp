defmodule HeadsUp.Settlement.Worker do
  @moduledoc """
  Makes settlement AUTOMATIC: a supervised GenServer that self-ticks on a config
  interval, sweeps every duel whose scoring window has closed, and settles each
  with per-duel error isolation (one bad duel never aborts the sweep or crashes
  the process — it's just retried next tick). `trigger_now/0` forces an immediate
  synchronous sweep for tests/admin.
  """
  use GenServer

  require Logger

  alias HeadsUp.Settlement

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Force an immediate sweep (synchronous) — for tests/admin without waiting for the interval."
  def trigger_now, do: GenServer.call(__MODULE__, :sweep)

  @impl true
  def init(opts) do
    interval =
      Keyword.get(opts, :interval_ms, Application.get_env(:heads_up, :settlement_interval_ms, 60_000))

    now_fun = Keyword.get(opts, :now_fun, &DateTime.utc_now/0)
    schedule(interval)
    {:ok, %{interval: interval, now_fun: now_fun}}
  end

  @impl true
  def handle_info(:tick, state) do
    sweep(state.now_fun)
    schedule(state.interval)
    {:noreply, state}
  end

  @impl true
  def handle_call(:sweep, _from, state) do
    {:reply, sweep(state.now_fun), state}
  end

  defp sweep(now_fun) do
    for duel <- Settlement.due_duels(now_fun.()) do
      try do
        case Settlement.settle_duel(duel.id) do
          {:ok, _result, _duel} -> :ok
          {:ok, _duel} -> :ok
          # Expected-transient (a real 5b feed not yet final): info, will retry.
          {:error, :stats_not_final} -> Logger.info("settlement deferred for duel=#{duel.id}: stats not final")
          # Stuck (bad data): surface it so an operator can act, instead of retrying silently forever.
          {:error, reason} -> Logger.warning("settlement failed for duel=#{duel.id}: #{inspect(reason)}")
        end
      rescue
        e -> Logger.error("settlement crashed for duel=#{duel.id}: #{Exception.message(e)}")
      catch
        kind, reason -> Logger.error("settlement crashed for duel=#{duel.id}: #{inspect({kind, reason})}")
      end
    end

    :ok
  end

  defp schedule(ms), do: Process.send_after(self(), :tick, ms)
end
