defmodule HeadsUp.Drafts.AutoPick do
  @moduledoc """
  The auto-pick rule for a timed-out / disconnected pick: rank-first but
  position-aware. Walk available players by descending projection and take the
  FIRST one whose position fits an open lineup slot — so if the very top
  player's slot is already full, we defer to the next-best player at a slot the
  team can still fill (FLEX/UTIL eligibility handled by `Lineup.can_fill?/3`).
  """
  alias HeadsUp.Drafts.Lineup

  @doc """
  Pick from `available` (a list or `%{id => player}` map of player maps, each
  with `:id`, `:position`, `:projection`) for a team whose `filled` slot keys
  and lineup `slots` are given.

  Returns `{:ok, player_id, slot_key}`, or `:error` if no available player can
  fill any open slot (should be unreachable given pool sizing vs lineup size).
  """
  @spec pick(map() | list(), [String.t()], [map()]) :: {:ok, integer(), String.t()} | :error
  def pick(available, filled, slots) do
    available
    |> pool_list()
    |> Enum.sort_by(fn p -> {-p.projection, p.id} end)
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
