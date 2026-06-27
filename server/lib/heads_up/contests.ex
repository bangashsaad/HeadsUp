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
  alias HeadsUp.Drafts.Lineup

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

  @doc """
  Internal: the draft engine flips an accepted duel to "drafting" when its
  live draft begins. Idempotent if the duel already advanced past accepted.
  """
  def start_draft(duel_id) do
    case Repo.get(Duel, duel_id) do
      %Duel{status: "accepted"} = duel -> duel |> Duel.status_changeset("drafting") |> Repo.update()
      %Duel{} = duel -> {:ok, duel}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Internal: the draft engine flips a duel to "drafted" when the draft completes,
  and FREEZES the scoring window (anchored at completion, so the draft is always
  locked before the window opens). The settlement worker sweeps on its close.
  """
  def finish_draft(duel_id) do
    case Repo.get(Duel, duel_id) do
      %Duel{} = duel ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        window_seconds = Application.get_env(:heads_up, :scoring_window_seconds, 86_400)

        duel
        |> Duel.finish_changeset(%{
          status: "drafted",
          scoring_window_start: now,
          scoring_window_end: DateTime.add(now, window_seconds, :second)
        })
        |> Repo.update()

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Internal: a draft was cancelled (no-show / abort) — return the duel to
  "cancelled". No forfeit win. Idempotent if already past drafting.
  """
  def cancel_drafting(duel_id) do
    case Repo.get(Duel, duel_id) do
      %Duel{status: s} = duel when s in ["accepted", "drafting"] ->
        duel |> Duel.status_changeset("cancelled") |> Repo.update()

      %Duel{} = duel ->
        {:ok, duel}

      nil ->
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

  @doc """
  The duel for a draft room: returned only to a participant, and only once the
  duel is accepted (or already drafting/drafted, so a room can be resumed/viewed).
  Used by the DraftChannel to authorize a join. nil otherwise.
  """
  def get_duel_for_draft(user_id, duel_id) do
    from(d in Duel,
      where:
        d.id == ^duel_id and
          (d.challenger_id == ^user_id or d.opponent_id == ^user_id) and
          d.status in ["accepted", "drafting", "drafted"],
      preload: [:challenger, :opponent]
    )
    |> Repo.one()
  end

  # --- helpers ---

  # Fills in server-controlled fields and per-sport scoring defaults.
  # roster_size is DERIVED from the lineup template so pick count always matches.
  defp build_attrs(challenger, attrs) do
    sport = attrs["sport"]
    template = attrs["lineup_template"] || "#{sport}_standard"

    attrs
    |> Map.put("challenger_id", challenger.id)
    |> Map.put("status", "pending")
    |> Map.put("lineup_template", template)
    |> Map.put("roster_size", Lineup.slot_count(template))
    |> Map.put_new("draft_type", "snake")
    |> Map.put_new("pick_clock_seconds", 60)
    |> Map.put_new("wager_cents", 0)
    |> Map.put_new("scoring_rules", Scoring.default_rules(sport))
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
