defmodule HeadsUp.Drafts.Supervisor do
  @moduledoc """
  DynamicSupervisor owning one `HeadsUp.Drafts.Server` per live draft. The
  channel calls `ensure_started/3` on join — idempotent, so both phones joining
  converge on a single server process.
  """
  use DynamicSupervisor

  alias HeadsUp.Drafts.Server

  def start_link(_opts), do: DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc """
  Start (or return the already-running) draft server for `draft_id`. `duel` is
  the loaded duel (sport, lineup_template, pick_clock_seconds, challenger_id,
  opponent_id). `opts` may inject `:rng` / `:now_fun` for tests.
  """
  def ensure_started(draft_id, duel, opts \\ []) do
    spec = {Server, [draft_id: draft_id, duel: duel] ++ opts}

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end
end
