defmodule HeadsUp.Contests.Events do
  @moduledoc """
  One fact, fanned out: a duel's status changed. Every status writer calls
  `duel_changed/1` after its commit; everyone seated on the duel gets
  `"duel_changed"` on their personal topic `user:<id>` — the website's
  LiveViews re-render and the phone's `UserChannel` refetches. Fire-and-
  forget: a broadcast can never fail a transition.
  """
  import Ecto.Query, warn: false

  alias HeadsUp.Repo
  alias HeadsUp.Contests.{Duel, Participant}

  def topic(user_id), do: "user:#{user_id}"

  def duel_changed(%Duel{id: id}), do: duel_changed(id)

  def duel_changed(duel_id) when is_integer(duel_id) do
    case Repo.get(Duel, duel_id) do
      nil ->
        :ok

      duel ->
        payload = %{duel_id: duel.id, status: duel.status}

        for uid <- audience(duel) do
          HeadsUpWeb.Endpoint.broadcast(topic(uid), "duel_changed", payload)
        end

        :ok
    end
  rescue
    _ -> :ok
  end

  def duel_changed(_), do: :ok

  # Host, the 1v1 opponent, and every seat (invited ones included — a
  # cancelled invite should vanish from their list too).
  defp audience(duel) do
    seats = Repo.all(from(p in Participant, where: p.duel_id == ^duel.id, select: p.user_id))
    Enum.uniq(Enum.reject([duel.challenger_id, duel.opponent_id | seats], &is_nil/1))
  end
end
