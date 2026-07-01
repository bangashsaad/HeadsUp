defmodule HeadsUp.Home do
  @moduledoc """
  Assembles the home dashboard for a user: the duels needing action, the ones in
  flight, the freshest results, and a record snapshot. Pure DB work (no ESPN) so
  the landing screen is instant — tonight's games load separately on the client.
  """
  alias HeadsUp.{Contests, Stats}
  alias HeadsUp.Accounts.User

  @doc """
  Returns the dashboard buckets for `user`, each a list of `%Duel{}` (both users
  preloaded), newest-activity first, plus the user's overall record.

    * `needs_response` — pending challenges where the user is the one to reply
    * `draft_ready`    — accepted/drafting duels to enter the draft room
    * `awaiting`       — drafted duels waiting on their scoring window to settle
    * `recent_results` — the 3 most recently settled duels
  """
  def summary(%User{id: id} = user) do
    duels = Contests.list_duels(user)

    %{
      needs_response: Enum.filter(duels, &(&1.status == "pending" and &1.opponent_id == id)),
      waiting_on_them: Enum.filter(duels, &(&1.status == "pending" and &1.challenger_id == id)),
      draft_ready: Enum.filter(duels, &(&1.status in ["accepted", "drafting"])),
      awaiting: Enum.filter(duels, &(&1.status == "drafted")),
      recent_results: duels |> Enum.filter(&(&1.status == "settled")) |> Enum.take(3),
      record: Stats.record_for(id)
    }
  end
end
