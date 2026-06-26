defmodule HeadsUp.Contests do
  @moduledoc """
  The Contests context: creating challenges (duels), and the
  accept / decline / counter / cancel lifecycle.

  A duel flows: pending -> accepted | declined | cancelled | countered.
  A counter marks the old duel "countered" and creates a fresh pending duel
  in the other direction, pointing back at it via parent_duel_id.
  """

  import Ecto.Query, warn: false
  alias HeadsUp.Repo
  alias HeadsUp.Accounts.User
  alias HeadsUp.Social
  alias HeadsUp.Contests.{Duel, Scoring}

  @doc "Creates a challenge from `challenger` to a friend."
  def create_challenge(%User{} = challenger, attrs) do
    opponent_id = attrs["opponent_id"]

    cond do
      to_string(opponent_id) == to_string(challenger.id) ->
        {:error, "you can't challenge yourself"}

      not Social.friends?(challenger, opponent_id) ->
        {:error, "you can only challenge your friends"}

      true ->
        %Duel{}
        |> Duel.create_changeset(build_attrs(challenger, attrs))
        |> Repo.insert()
        |> with_users()
    end
  end

  @doc "Opponent accepts a pending challenge."
  def accept_challenge(%User{} = user, id) do
    transition(user, id, :opponent, "pending", "accepted")
  end

  @doc "Opponent declines a pending challenge."
  def decline_challenge(%User{} = user, id) do
    transition(user, id, :opponent, "pending", "declined")
  end

  @doc "Challenger cancels their own pending challenge."
  def cancel_challenge(%User{} = user, id) do
    transition(user, id, :challenger, "pending", "cancelled")
  end

  @doc """
  Opponent counters a pending challenge with new terms: marks the original
  "countered" and creates a new pending duel in the opposite direction.
  """
  def counter_challenge(%User{} = user, id, new_attrs) do
    case Repo.get(Duel, id) do
      %Duel{opponent_id: oid, challenger_id: cid, status: "pending"} = original
      when oid == user.id ->
        attrs =
          new_attrs
          |> Map.put("opponent_id", cid)
          |> Map.put("parent_duel_id", original.id)

        Ecto.Multi.new()
        |> Ecto.Multi.update(:original, Duel.status_changeset(original, "countered"))
        |> Ecto.Multi.insert(:counter, fn _ ->
          Duel.create_changeset(%Duel{}, build_attrs(user, attrs))
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{counter: counter}} -> with_users({:ok, counter})
          {:error, _step, changeset, _} -> {:error, changeset}
        end

      _ ->
        {:error, :not_found}
    end
  end

  @doc "All duels the user is part of, newest first, with both users preloaded."
  def list_duels(%User{id: id}) do
    from(d in Duel,
      where: d.challenger_id == ^id or d.opponent_id == ^id,
      order_by: [desc: d.updated_at],
      preload: [:challenger, :opponent]
    )
    |> Repo.all()
  end

  @doc "A single duel the user is part of (or nil), with both users preloaded."
  def get_duel(%User{id: id}, duel_id) do
    from(d in Duel,
      where: d.id == ^duel_id and (d.challenger_id == ^id or d.opponent_id == ^id),
      preload: [:challenger, :opponent]
    )
    |> Repo.one()
  end

  # --- helpers ---

  # Fills in server-controlled fields and per-sport scoring defaults.
  defp build_attrs(challenger, attrs) do
    attrs
    |> Map.put("challenger_id", challenger.id)
    |> Map.put("status", "pending")
    |> Map.put_new("draft_type", "snake")
    |> Map.put_new("wager_cents", 0)
    |> Map.put_new("scoring_rules", Scoring.default_rules(attrs["sport"]))
  end

  # Generic guarded status change: the duel must be at `from_status` and the
  # acting user must hold the given `role`.
  defp transition(%User{id: uid}, id, role, from_status, to_status) do
    duel = Repo.get(Duel, id)

    cond do
      is_nil(duel) -> {:error, :not_found}
      duel.status != from_status -> {:error, :not_found}
      role == :opponent and duel.opponent_id != uid -> {:error, :not_found}
      role == :challenger and duel.challenger_id != uid -> {:error, :not_found}
      true -> duel |> Duel.status_changeset(to_status) |> Repo.update() |> with_users()
    end
  end

  # Preload both players so the JSON view can render the duel.
  defp with_users({:ok, duel}), do: {:ok, Repo.preload(duel, [:challenger, :opponent])}
  defp with_users(other), do: other
end
