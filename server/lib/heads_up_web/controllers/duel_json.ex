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
  player is, the full agreed terms, and status.
  """
  def data(%Duel{} = duel, current_user_id) do
    {role, other} =
      if duel.challenger_id == current_user_id do
        {"challenger", duel.opponent}
      else
        {"opponent", duel.challenger}
      end

    %{
      id: duel.id,
      status: duel.status,
      role: role,
      opponent: PublicUserJSON.public(other),
      sport: duel.sport,
      draft_type: duel.draft_type,
      roster_size: duel.roster_size,
      scoring_rules: duel.scoring_rules,
      wager_cents: duel.wager_cents,
      draft_starts_at: duel.draft_starts_at,
      parent_duel_id: duel.parent_duel_id,
      inserted_at: duel.inserted_at
    }
  end
end
