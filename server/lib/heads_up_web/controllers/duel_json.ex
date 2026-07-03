defmodule HeadsUpWeb.DuelJSON do
  alias HeadsUp.Contests.Duel
  alias HeadsUpWeb.PublicUserJSON

  def index(%{duels: duels, current_user_id: uid}) do
    %{duels: Enum.map(duels, &data(&1, uid))}
  end

  def show(%{duel: duel, current_user_id: uid}) do
    %{duel: data(duel, uid)}
  end

  @doc """
  A duel from the current user's point of view: their role, who the other
  player is (for a group: the host, or your first invitee), the seats, the
  full agreed terms, and status.
  """
  def data(%Duel{} = duel, current_user_id) do
    group = is_nil(duel.opponent_id)
    participants = participants_list(duel)

    {role, other} =
      if duel.challenger_id == current_user_id do
        {"challenger", duel.opponent || first_invitee(participants)}
      else
        {"opponent", duel.challenger}
      end

    %{
      id: duel.id,
      status: duel.status,
      role: role,
      opponent: other && PublicUserJSON.public(other),
      group: group,
      party_size: if(group, do: length(participants), else: 2),
      participants:
        for p <- participants do
          %{seat: p.seat, status: p.status, user: PublicUserJSON.public(p.user)}
        end,
      sport: duel.sport,
      draft_type: duel.draft_type,
      roster_size: duel.roster_size,
      lineup_template: duel.lineup_template,
      pick_clock_seconds: duel.pick_clock_seconds,
      scoring_rules: duel.scoring_rules,
      wager_cents: duel.wager_cents,
      draft_starts_at: duel.draft_starts_at,
      scoring_window_end: duel.scoring_window_end,
      # Settlement outcome (present once status == "settled"; winner_id nil = tie).
      winner_id: duel.winner_id,
      settled_at: duel.settled_at,
      my_outcome: outcome(duel, current_user_id),
      parent_duel_id: duel.parent_duel_id,
      inserted_at: duel.inserted_at
    }
  end

  defp participants_list(%Duel{participants: participants}) when is_list(participants) do
    participants |> Enum.filter(& &1.user) |> Enum.sort_by(& &1.seat)
  end

  defp participants_list(_duel), do: []

  defp first_invitee(participants) do
    case Enum.find(participants, &(&1.seat > 0)) do
      nil -> nil
      p -> p.user
    end
  end

  # win / loss / tie from the viewer's POV, or nil until settled.
  defp outcome(%Duel{status: "settled"} = duel, uid) do
    cond do
      is_nil(duel.winner_id) -> "tie"
      duel.winner_id == uid -> "win"
      true -> "loss"
    end
  end

  defp outcome(_duel, _uid), do: nil
end
