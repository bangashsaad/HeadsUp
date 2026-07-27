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
      stake_coins: duel.stake_coins,
      pot_coins: pot_coins(duel, group, participants),
      slate_date: duel.slate_date,
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

  # The pot on the table: stake × players. While a group is still pending the
  # undecided seats count (the pot if everyone's in); once it starts, only the
  # seats that actually staked do.
  defp pot_coins(%Duel{stake_coins: 0}, _group, _participants), do: 0
  defp pot_coins(%Duel{} = duel, false, _participants), do: duel.stake_coins * 2

  defp pot_coins(%Duel{} = duel, true, participants) do
    live =
      if duel.status == "pending" do
        Enum.count(participants, &(&1.status in ["accepted", "invited"]))
      else
        Enum.count(participants, &(&1.status == "accepted"))
      end

    duel.stake_coins * live
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
