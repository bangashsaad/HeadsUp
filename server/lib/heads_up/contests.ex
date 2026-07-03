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
  alias HeadsUp.Contests.{Duel, Participant, Scoring}
  alias HeadsUp.Drafts.Lineup

  @doc """
  Creates a challenge from `challenger` to one friend (`"opponent_id"`) or, for
  a group duel, several (`"opponent_ids"`, 2..3 of them — 3-4 players total).
  """
  def create_challenge(%User{} = challenger, attrs) do
    case List.wrap(attrs["opponent_ids"]) do
      ids when length(ids) >= 2 ->
        create_group_challenge(challenger, attrs)

      [single] ->
        create_challenge(challenger, attrs |> Map.delete("opponent_ids") |> Map.put("opponent_id", single))

      [] ->
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
            |> seed_participants()
            |> with_users()
            |> notify_challenged()
        end
    end
  end

  @doc """
  Creates a group duel: the host takes seat 0 (accepted); each invited friend
  gets their own seat to accept or decline. Invitees only need to be friends
  with the HOST. The duel goes "accepted" once every non-declined seat is in.
  """
  def create_group_challenge(%User{} = challenger, attrs) do
    invitee_ids =
      attrs["opponent_ids"] |> List.wrap() |> Enum.map(&normalize_id/1) |> Enum.uniq()

    cond do
      Enum.any?(invitee_ids, &is_nil/1) ->
        {:error, "invalid opponent list"}

      length(invitee_ids) < 2 ->
        {:error, "a group duel needs at least 2 invitees"}

      length(invitee_ids) > Participant.max_seat() ->
        {:error, "a duel holds at most #{Participant.max_seat() + 1} players"}

      challenger.id in invitee_ids ->
        {:error, "you can't challenge yourself"}

      not Enum.all?(invitee_ids, &Social.friends?(challenger, &1)) ->
        {:error, "you can only challenge your friends"}

      true ->
        insert_group(challenger, invitee_ids, attrs)
    end
  end

  defp insert_group(challenger, invitee_ids, attrs) do
    attrs = attrs |> Map.delete("opponent_ids") |> Map.put("opponent_id", nil)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:duel, Duel.group_create_changeset(%Duel{}, build_attrs(challenger, attrs)))
    |> Ecto.Multi.run(:seats, fn repo, %{duel: duel} ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        [%{duel_id: duel.id, user_id: challenger.id, seat: 0, status: "accepted", inserted_at: now, updated_at: now}] ++
          (invitee_ids
           |> Enum.with_index(1)
           |> Enum.map(fn {uid, seat} ->
             %{duel_id: duel.id, user_id: uid, seat: seat, status: "invited", inserted_at: now, updated_at: now}
           end))

      {count, _} = repo.insert_all(Participant, rows)
      {:ok, count}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{duel: duel}} ->
        duel = preload_all(duel)
        notify_group_invites(duel)
        {:ok, duel}

      {:error, _step, %Ecto.Changeset{} = changeset, _} ->
        {:error, changeset}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  defp normalize_id(id) when is_integer(id), do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp normalize_id(_), do: nil

  @doc "Opponent accepts a pending challenge (their own seat, in a group duel)."
  def accept_challenge(%User{} = user, id) do
    case Repo.get(Duel, id) do
      %Duel{opponent_id: nil, status: "pending"} = duel -> seat_respond(user, duel, "accepted")
      _ -> transition(user, id, :opponent, "pending", "accepted")
    end
  end

  @doc "Opponent declines a pending challenge (their own seat, in a group duel)."
  def decline_challenge(%User{} = user, id) do
    case Repo.get(Duel, id) do
      %Duel{opponent_id: nil, status: "pending"} = duel -> seat_respond(user, duel, "declined")
      _ -> transition(user, id, :opponent, "pending", "declined")
    end
  end

  @doc "Challenger cancels their own pending challenge."
  def cancel_challenge(%User{} = user, id) do
    transition(user, id, :challenger, "pending", "cancelled")
  end

  @doc """
  Host force-start for a group duel: drop everyone still deciding (their seats
  flip to declined) and start with the current group. Needs ≥ 2 accepted seats.
  """
  def start_with_group(%User{id: uid}, id) do
    duel = Repo.get(Duel, id)

    cond do
      is_nil(duel) or duel.status != "pending" or not group?(duel) -> {:error, :not_found}
      duel.challenger_id != uid -> {:error, :not_found}
      true -> force_start(duel)
    end
  end

  defp force_start(duel) do
    seats = list_participants(duel.id)
    accepted = Enum.filter(seats, &(&1.status == "accepted"))

    if length(accepted) >= 2 do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      from(p in Participant, where: p.duel_id == ^duel.id and p.status == "invited")
      |> Repo.update_all(set: [status: "declined", updated_at: now])

      with {:ok, fresh} <- duel |> Duel.status_changeset("accepted") |> Repo.update() do
        notify_group_ready(fresh, Enum.map(accepted, & &1.user_id) -- [duel.challenger_id])
        {:ok, preload_all(fresh)}
      end
    else
      {:error, :not_enough_players}
    end
  end

  @doc """
  Rematch: create a fresh pending challenge from `user` to the OTHER participant
  of `duel_id`, cloning its terms (sport, lineup, clock, scoring). `attrs` may
  override `"draft_starts_at"`; otherwise it defaults to ~15 min out. Links back
  via `parent_duel_id`.
  """
  def rematch(%User{} = user, duel_id, attrs \\ %{}) do
    case get_duel(user, duel_id) do
      nil ->
        {:error, :not_found}

      # Group rematch (re-invite the same seats) ships with the group UI.
      %Duel{opponent_id: nil} ->
        {:error, :not_found}

      %Duel{} = duel ->
        other = if duel.challenger_id == user.id, do: duel.opponent_id, else: duel.challenger_id

        create_challenge(user, %{
          "opponent_id" => other,
          "sport" => duel.sport,
          "lineup_template" => duel.lineup_template,
          "draft_type" => duel.draft_type,
          "pick_clock_seconds" => duel.pick_clock_seconds,
          "scoring_rules" => duel.scoring_rules,
          "wager_cents" => duel.wager_cents,
          "draft_starts_at" => attrs["draft_starts_at"] || default_rematch_start(),
          "parent_duel_id" => duel.id
        })
    end
  end

  defp default_rematch_start do
    DateTime.utc_now() |> DateTime.add(900, :second) |> DateTime.truncate(:second) |> DateTime.to_iso8601()
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
          {:ok, %{counter: counter}} -> {:ok, counter} |> seed_participants() |> with_users() |> notify_challenged()
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

  @doc "All duels the user holds a seat in, newest first, users + seats preloaded."
  def list_duels(%User{id: id}) do
    from(d in Duel,
      left_join: p in Participant,
      on: p.duel_id == d.id and p.user_id == ^id,
      where: not is_nil(p.id) or d.challenger_id == ^id or d.opponent_id == ^id,
      order_by: [desc: d.updated_at],
      preload: [:challenger, :opponent, participants: :user]
    )
    |> Repo.all()
  end

  @doc "A single duel the user holds a seat in (or nil), users + seats preloaded."
  def get_duel(%User{id: id}, duel_id) do
    from(d in Duel,
      left_join: p in Participant,
      on: p.duel_id == d.id and p.user_id == ^id,
      where: d.id == ^duel_id and (not is_nil(p.id) or d.challenger_id == ^id or d.opponent_id == ^id),
      preload: [:challenger, :opponent, participants: :user]
    )
    |> Repo.one()
  end

  @doc """
  The duel for a draft room: returned only to a player of the match (an
  ACCEPTED seat, for group duels), and only once the duel is accepted (or
  already drafting/drafted, so a room can be resumed/viewed). Used by the
  DraftChannel to authorize a join. nil otherwise.
  """
  def get_duel_for_draft(user_id, duel_id) do
    from(d in Duel,
      left_join: p in Participant,
      on: p.duel_id == d.id and p.user_id == ^user_id,
      where:
        d.id == ^duel_id and
          d.status in ["accepted", "drafting", "drafted"] and
          (d.challenger_id == ^user_id or d.opponent_id == ^user_id or
             (not is_nil(p.id) and p.status == "accepted")),
      preload: [:challenger, :opponent, participants: :user]
    )
    |> Repo.one()
  end

  @doc "True when the duel is a group contest (seats are the roster of players)."
  def group?(%Duel{opponent_id: nil}), do: true
  def group?(%Duel{}), do: false

  @doc """
  The user_ids actually PLAYING this duel, in seat order. 1v1 = challenger then
  opponent; group = every accepted seat. The draft engine and settlement key
  their state off this list.
  """
  def player_ids(%Duel{opponent_id: nil} = duel) do
    from(p in Participant,
      where: p.duel_id == ^duel.id and p.status == "accepted",
      order_by: [asc: p.seat],
      select: p.user_id
    )
    |> Repo.all()
  end

  def player_ids(%Duel{} = duel), do: [duel.challenger_id, duel.opponent_id]

  @doc "The players of a duel as `[%{id, username}]` in seat order (for the draft room)."
  def draft_players(%Duel{opponent_id: nil} = duel) do
    from(p in Participant,
      join: u in assoc(p, :user),
      where: p.duel_id == ^duel.id and p.status == "accepted",
      order_by: [asc: p.seat],
      select: %{id: u.id, username: u.username}
    )
    |> Repo.all()
  end

  def draft_players(%Duel{} = duel) do
    duel = Repo.preload(duel, [:challenger, :opponent])

    [
      %{id: duel.challenger.id, username: duel.challenger.username},
      %{id: duel.opponent.id, username: duel.opponent.username}
    ]
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
      true -> duel |> Duel.status_changeset(to_status) |> Repo.update() |> sync_seat(uid, to_status) |> with_users()
    end
  end

  @doc "All seats for a duel, host first, with users preloaded."
  def list_participants(duel_id) do
    from(p in Participant, where: p.duel_id == ^duel_id, order_by: [asc: p.seat], preload: [:user])
    |> Repo.all()
  end

  # An invitee answers their own seat. The duel then re-derives its status:
  # every live seat accepted (≥2 in) -> accepted; collapsed below 2 -> cancelled;
  # otherwise it stays pending while stragglers decide.
  defp seat_respond(%User{} = actor, %Duel{} = duel, new_status) do
    seat = Repo.get_by(Participant, duel_id: duel.id, user_id: actor.id)

    cond do
      is_nil(seat) or seat.seat == 0 or seat.status != "invited" ->
        {:error, :not_found}

      true ->
        {:ok, _} = seat |> Participant.changeset(%{status: new_status}) |> Repo.update()
        resolve_group_status(duel, actor, new_status)
    end
  end

  defp resolve_group_status(%Duel{} = duel, %User{} = actor, responded_with) do
    seats = list_participants(duel.id)
    accepted_ids = seats |> Enum.filter(&(&1.status == "accepted")) |> Enum.map(& &1.user_id)
    pending = Enum.count(seats, &(&1.status == "invited"))
    live = length(accepted_ids) + pending

    duel_status =
      cond do
        live < 2 -> "cancelled"
        pending == 0 and length(accepted_ids) >= 2 -> "accepted"
        true -> nil
      end

    result =
      case duel_status do
        nil -> {:ok, duel}
        status -> duel |> Duel.status_changeset(status) |> Repo.update()
      end

    with {:ok, fresh} <- result do
      cond do
        # Everyone's in (the actor already knows — they just tapped).
        duel_status == "accepted" -> notify_group_ready(fresh, accepted_ids -- [actor.id])
        duel_status == "cancelled" -> notify_group_cancelled(fresh, actor.username)
        responded_with == "declined" -> notify_group_shrunk(fresh, actor.username, live)
        true -> :ok
      end

      {:ok, preload_all(fresh)}
    end
  end

  # Every duel gets a seat row per player: seat 0 = host (auto-accepted),
  # invitees follow. For 1v1 this shadows challenger/opponent; the multiplayer
  # engine reads seats as the source of truth.
  defp seed_participants({:ok, duel} = result) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      Participant,
      [
        %{duel_id: duel.id, user_id: duel.challenger_id, seat: 0, status: "accepted", inserted_at: now, updated_at: now},
        %{duel_id: duel.id, user_id: duel.opponent_id, seat: 1, status: "invited", inserted_at: now, updated_at: now}
      ],
      on_conflict: :nothing
    )

    result
  end

  defp seed_participants(other), do: other

  # Mirror an accept/decline onto the actor's seat row (cancel leaves seats be).
  defp sync_seat({:ok, duel} = result, uid, to_status) when to_status in ["accepted", "declined"] do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(p in Participant, where: p.duel_id == ^duel.id and p.user_id == ^uid)
    |> Repo.update_all(set: [status: to_status, updated_at: now])

    result
  end

  defp sync_seat(result, _uid, _to_status), do: result

  # Preload both players + seats so the JSON view can render the duel.
  defp with_users({:ok, duel}), do: {:ok, preload_all(duel)}
  defp with_users(other), do: other

  defp preload_all(duel), do: Repo.preload(duel, [:challenger, :opponent, participants: :user], force: true)

  # Push "you were challenged" to the recipient (fire-and-forget; pass-through).
  defp notify_challenged({:ok, duel} = result) do
    HeadsUp.Notifications.notify_user(
      duel.opponent_id,
      "New challenge ⚔️",
      "#{duel.challenger.username} challenged you to a #{String.upcase(duel.sport)} duel",
      %{type: "duel", duel_id: duel.id}
    )

    result
  end

  defp notify_challenged(other), do: other

  # --- group pushes (fire-and-forget) --------------------------------------

  defp notify_group_invites(%Duel{} = duel) do
    host = duel.challenger.username
    players = length(duel.participants)

    for p <- duel.participants, p.seat > 0 do
      HeadsUp.Notifications.notify_user(
        p.user_id,
        "Group duel invite ⚔️",
        "#{host} invited you to a #{players}-player #{String.upcase(duel.sport)} duel",
        %{type: "duel", duel_id: duel.id}
      )
    end

    :ok
  end

  defp notify_group_ready(%Duel{} = duel, user_ids) do
    for uid <- user_ids do
      HeadsUp.Notifications.notify_user(
        uid,
        "Everyone's in ✅",
        "Your #{String.upcase(duel.sport)} group duel is ready to draft",
        %{type: "duel", duel_id: duel.id}
      )
    end

    :ok
  end

  defp notify_group_shrunk(%Duel{} = duel, decliner, players_left) do
    HeadsUp.Notifications.notify_user(
      duel.challenger_id,
      "Seat declined",
      "#{decliner} declined — your group duel is down to #{players_left} players",
      %{type: "duel", duel_id: duel.id}
    )
  end

  defp notify_group_cancelled(%Duel{} = duel, decliner) do
    HeadsUp.Notifications.notify_user(
      duel.challenger_id,
      "Duel cancelled",
      "#{decliner} declined and not enough players remain",
      %{type: "duel", duel_id: duel.id}
    )
  end
end
