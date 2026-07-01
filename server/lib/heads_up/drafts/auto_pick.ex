defmodule HeadsUp.Drafts.AutoPick do
  @moduledoc """
  The auto-pick rule for a timed-out / disconnected pick: the user's QUEUE first,
  then rank-first — always position-aware. Take the first still-available queued
  player (in the user's priority order) whose position fits an open lineup slot;
  if the queue is empty or exhausted, fall back to descending projection. Slot
  eligibility (FLEX/UTIL) is handled by `Lineup.can_fill?/3`.
  """
  alias HeadsUp.Drafts.Lineup

  @doc """
  Pick from `available` (a list or `%{id => player}` map of player maps, each
  with `:id`, `:position`, `:projection`) for a team whose `filled` slot keys
  and lineup `slots` are given. `queue` is the user's priority list of
  player_ids (default `[]`); still-available queued players are tried first, in
  order, before the projection ranking.

  Returns `{:ok, player_id, slot_key}`, or `:error` if no available player can
  fill any open slot (should be unreachable given pool sizing vs lineup size).
  """
  @spec pick(map() | list(), [String.t()], [map()], [integer()]) :: {:ok, integer(), String.t()} | :error
  def pick(available, filled, slots, queue \\ []) do
    pool = pool_list(available)
    by_id = Map.new(pool, &{&1.id, &1})
    queued = queue |> Enum.map(&Map.get(by_id, &1)) |> Enum.reject(&is_nil/1)
    queued_ids = MapSet.new(queued, & &1.id)
    ranked = Enum.sort_by(pool, fn p -> {-p.projection, p.id} end)

    (queued ++ Enum.reject(ranked, &MapSet.member?(queued_ids, &1.id)))
    |> Enum.find_value(:error, fn p ->
      case Lineup.can_fill?(slots, filled, p.position) do
        {:ok, slot_key} -> {:ok, p.id, slot_key}
        :error -> false
      end
    end)
  end

  defp pool_list(m) when is_map(m), do: Map.values(m)
  defp pool_list(l) when is_list(l), do: l
end
