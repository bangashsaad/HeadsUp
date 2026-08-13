defmodule HeadsUp.Heartbeat do
  @moduledoc """
  A last-ran timestamp per background worker, so `HeadsUp.Health` can tell a
  worker that is running from one that is merely alive. The janitor sat alive
  and idle for weeks — its process was up the whole time, which is exactly why
  process liveness is not the thing worth measuring.

  ETS rather than `:persistent_term`: these are written every worker pass, and
  a persistent_term write triggers a global scan. Values do not survive a
  restart, which is the semantics we want — a rebooted node genuinely has not
  swept yet.
  """

  @table :heads_up_heartbeats

  @doc "Create the table. Called once from the application supervisor."
  def init_table do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Stamp `name` as having just run."
  def record(name) do
    ensure_table()
    :ets.insert(@table, {name, System.system_time(:second)})
    :ok
  end

  @doc "Seconds since `name` last ran, or nil if it never has on this node."
  def age_seconds(name) do
    case lookup(name) do
      nil -> nil
      at -> System.system_time(:second) - at
    end
  end

  defp lookup(name) do
    case :ets.lookup(@table, name) do
      [{^name, at}] -> at
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined, do: init_table(), else: :ok
  end
end
