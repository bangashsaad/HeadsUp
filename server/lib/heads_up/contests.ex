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
  alias HeadsUp.Coins
  alias HeadsUp.Social
  alias HeadsUp.Contests.{Duel, Participant, Scoring}
  alias HeadsUp.Drafts.Lineup
  alias HeadsUp.Sports.{Player, Season, Slate}

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

          not Season.in_season?(attrs["sport"]) ->
            {:error, off_season_message(attrs["sport"])}

          true ->
            # Duel + the challenger's stake land (or fail) together: not enough
            # coins means no duel row at all.
            with {:ok, built} <- resolve_slate(build_attrs(challenger, attrs), 2) do
              Ecto.Multi.new()
              |> Ecto.Multi.insert(:duel, Duel.create_changeset(%Duel{}, built))
              |> Ecto.Multi.run(:stake, fn repo, %{duel: duel} ->
                Coins.stake(repo, challenger.id, duel.id, duel.stake_coins)
              end)
              |> Repo.transaction()
              |> case do
                {:ok, %{duel: duel}} ->
                  {:ok, duel} |> seed_participants() |> with_users() |> notify_challenged()

                {:error, _step, %Ecto.Changeset{} = changeset, _} ->
                  {:error, changeset}

                {:error, _step, reason, _} ->
                  {:error, reason}
              end
            end
        end
    end
  end

  defp off_season_message(sport) do
    "#{String.upcase(to_string(sport))} has no games in the next #{Season.window_days()} days — pick an in-season sport"
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

      not Season.in_season?(attrs["sport"]) ->
        {:error, off_season_message(attrs["sport"])}

      true ->
        insert_group(challenger, invitee_ids, attrs)
    end
  end

  defp insert_group(challenger, invitee_ids, attrs) do
    attrs = attrs |> Map.delete("opponent_ids") |> Map.put("opponent_id", nil)

    with {:ok, built} <- resolve_slate(build_attrs(challenger, attrs), 1 + length(invitee_ids)) do
      do_insert_group(challenger, invitee_ids, built)
    end
  end

  defp do_insert_group(challenger, invitee_ids, built) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:duel, Duel.group_create_changeset(%Duel{}, built))
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
    |> Ecto.Multi.run(:stake, fn repo, %{duel: duel} ->
      # The host stakes at creation; each invitee stakes when their seat accepts.
      Coins.stake(repo, challenger.id, duel.id, duel.stake_coins)
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
  Rematch: clone `duel_id`'s terms into a fresh pending challenge from `user`.
  1v1 → the other player; group → re-invites everyone who PLAYED (accepted
  seats), with the tapper as the new host — a group that shrank to 2 players
  rematches as a classic 1v1. `attrs` may override `"draft_starts_at"`;
  otherwise it defaults to ~15 min out. Links back via `parent_duel_id`.
  """
  def rematch(%User{} = user, duel_id, attrs \\ %{}) do
    case get_duel(user, duel_id) do
      nil ->
        {:error, :not_found}

      %Duel{} = duel ->
        terms = %{
          "sport" => duel.sport,
          "lineup_template" => duel.lineup_template,
          "draft_type" => duel.draft_type,
          "pick_clock_seconds" => duel.pick_clock_seconds,
          "scoring_rules" => duel.scoring_rules,
          "stake_coins" => duel.stake_coins,
          "draft_starts_at" => attrs["draft_starts_at"] || default_rematch_start(),
          "parent_duel_id" => duel.id
        }

        case rematch_invitees(duel, user) do
          [] ->
            {:error, :not_found}

          [single] ->
            create_challenge(user, Map.put(terms, "opponent_id", single))

          # They all just played together — no friends check between the new
          # host and the re-invited seats (friendship gates NEW contacts).
          invitee_ids ->
            insert_group(user, invitee_ids, terms)
        end
    end
  end

  # Who gets re-invited: 1v1 → the other player; group → the accepted seats
  # minus the tapper (who must have held an accepted seat themselves — a
  # declined invitee can see the duel but has no rematch to offer).
  defp rematch_invitees(%Duel{opponent_id: nil} = duel, %User{id: uid}) do
    seated = duel.participants |> Enum.filter(&(&1.status == "accepted")) |> Enum.map(& &1.user_id)
    if uid in seated, do: seated -- [uid], else: []
  end

  defp rematch_invitees(%Duel{} = duel, %User{id: uid}) do
    [if(duel.challenger_id == uid, do: duel.opponent_id, else: duel.challenger_id)]
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

        with {:ok, built} <- resolve_slate(build_attrs(user, attrs), 2) do
          Ecto.Multi.new()
          |> Ecto.Multi.update(:original, Duel.status_changeset(original, "countered"))
          |> Ecto.Multi.run(:refund, fn repo, %{original: countered} ->
            # The original challenger's stake comes home; the counter-er stakes
            # the NEW terms' amount on the fresh duel below.
            Coins.refund(repo, countered.challenger_id, countered.id, countered.stake_coins)
          end)
          |> Ecto.Multi.insert(:counter, fn _ ->
            Duel.create_changeset(%Duel{}, built)
          end)
          |> Ecto.Multi.run(:stake, fn repo, %{counter: counter} ->
            Coins.stake(repo, user.id, counter.id, counter.stake_coins)
          end)
          |> Repo.transaction()
          |> case do
            {:ok, %{counter: counter}} -> {:ok, counter} |> seed_participants() |> with_users() |> notify_challenged()
            {:error, _step, changeset, _} -> {:error, changeset}
          end
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
      %Duel{status: status} = duel when status in ["accepted", "drafting"] ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        {window_start, window_end} = scoring_window(duel, now)

        duel
        |> Duel.finish_changeset(%{
          status: "drafted",
          scoring_window_start: window_start,
          scoring_window_end: window_end
        })
        |> Repo.update()

      # Terminal states are a quiet no-op success, NEVER a flip: a duel the
      # janitor (or anyone) cancelled mid-draft must not resurrect to
      # "drafted" — settlement would pay a pot whose stakes were already
      # refunded. No-op (vs error) keeps the engine's `{:ok, _} =` alive.
      %Duel{} = duel ->
        {:ok, duel}

      nil ->
        {:error, :not_found}
    end
  end

  # A slate duel scores exactly its ET calendar day (04:00 UTC → 03:59:59, the
  # same EDT convention as WindowScan), no matter when the draft wraps — the
  # pool filter already blocked drafting anyone whose game had tipped. Legacy
  # duels keep the anchored-at-completion window.
  defp scoring_window(%Duel{slate_date: %Date{} = slate}, _now) do
    window_start = DateTime.new!(slate, ~T[04:00:00], "Etc/UTC")
    {window_start, DateTime.add(window_start, 86_400 - 1, :second)}
  end

  defp scoring_window(_duel, now) do
    window_seconds = Application.get_env(:heads_up, :scoring_window_seconds, 86_400)
    {now, DateTime.add(now, window_seconds, :second)}
  end

  @doc """
  Internal: a draft was cancelled (no-show / abort) — return the duel to
  "cancelled". No forfeit win. Idempotent if already past drafting.
  """
  def cancel_drafting(duel_id) do
    case Repo.get(Duel, duel_id) do
      %Duel{status: s} = duel when s in ["accepted", "drafting"] ->
        Ecto.Multi.new()
        |> Ecto.Multi.update(:duel, Duel.status_changeset(duel, "cancelled"))
        |> Ecto.Multi.run(:coins, fn repo, %{duel: fresh} -> refund_staked(repo, fresh) end)
        |> Repo.transaction()
        |> case do
          {:ok, %{duel: fresh}} -> {:ok, fresh}
          {:error, _step, reason, _} -> {:error, reason}
        end

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
    |> Map.put_new("stake_coins", 0)
    |> Map.put_new("scoring_rules", Scoring.default_rules(sport))
  end

  # --- slates ---------------------------------------------------------------

  # Resolve a duel's slate on BUILT attrs (roster_size present): default to the
  # next ET day with games when the client didn't pick one, and guard a picked
  # day — real date, today..horizon, not before the draft day, and enough
  # draftable players for the format. Feed failures always fail OPEN (a nil
  # slate = legacy full-pool behavior; a kept date = the board filter's
  # problem later). Rematches and counters flow through here too.
  defp resolve_slate(built, nplayers) do
    case parse_slate_date(built["slate_date"]) do
      :absent -> {:ok, Map.put(built, "slate_date", default_slate_date(built, nplayers))}
      {:ok, date} -> validate_slate(built, date, nplayers)
      :invalid -> {:error, "that slate date isn't a real date"}
    end
  end

  defp parse_slate_date(nil), do: :absent
  defp parse_slate_date(""), do: :absent
  defp parse_slate_date(%Date{} = date), do: {:ok, date}

  defp parse_slate_date(iso) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> {:ok, date}
      _ -> :invalid
    end
  end

  defp parse_slate_date(_), do: :invalid

  # The server-picked default must clear the same bars as a user pick: games
  # that haven't tipped, a big enough pool, and never a day before the draft
  # (a slate already in the past at draft time can only score zeros).
  defp default_slate_date(built, nplayers) do
    sport = built["sport"]
    draft_day = draft_et_date(built["draft_starts_at"])
    need = (built["roster_size"] || 5) * nplayers * 2

    case Slate.upcoming(sport) do
      {:ok, days} ->
        Enum.find_value(days, fn d ->
          viable? =
            d.upcoming > 0 and
              (draft_day == nil or Date.compare(d.date, draft_day) != :lt) and
              slate_pool_count(sport, d.upcoming_teams) >= need

          if viable?, do: d.date
        end)

      {:error, _} ->
        nil
    end
  end

  defp validate_slate(built, date, nplayers) do
    sport = built["sport"]
    draft_day = draft_et_date(built["draft_starts_at"])

    cond do
      Date.compare(date, Slate.today()) == :lt ->
        {:error, "that slate already happened — pick today or later"}

      Date.compare(date, Slate.horizon()) == :gt ->
        {:error, "slates only go a week out — pick a closer day"}

      draft_day != nil and Date.compare(draft_day, date) == :gt ->
        {:error, "the draft has to happen on or before the slate day"}

      true ->
        case Slate.on(sport, date) do
          {:ok, %{games: 0}} ->
            {:error, "no #{String.upcase(to_string(sport))} games on that day — pick another slate"}

          # Games exist but they've all tipped/finished — drafting them now
          # would be picking known stat lines. (Only possible for today.)
          {:ok, %{upcoming: 0}} ->
            {:error, "tonight's slate has already tipped — pick tomorrow's games"}

          {:ok, %{upcoming_teams: teams}} ->
            need = (built["roster_size"] || 5) * nplayers * 2

            if slate_pool_count(sport, teams) >= need do
              {:ok, Map.put(built, "slate_date", date)}
            else
              {:error, "that slate is too small for this format — pick a day with more games"}
            end

          {:error, _} ->
            {:ok, Map.put(built, "slate_date", date)}
        end
    end
  end

  defp slate_pool_count(_sport, []), do: 0

  defp slate_pool_count(sport, teams) do
    from(p in Player, where: p.sport == ^sport and p.team in ^teams, select: count())
    |> Repo.one()
  end

  # The draft's ET calendar day (same UTC-4 convention as Slate/WindowScan).
  defp draft_et_date(%DateTime{} = dt),
    do: dt |> DateTime.add(-4 * 3600, :second) |> DateTime.to_date()

  defp draft_et_date(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> draft_et_date(dt)
      _ -> nil
    end
  end

  defp draft_et_date(_), do: nil

  # --- stale-duel sweep (the Janitor's queries) -----------------------------

  @doc """
  Expire duels that died on the vine, sending every escrowed stake home:

    * PENDING challenges nobody ever answered, `cutoff_hours` past their
      draft time — cancelled + the challenger's stake refunded.
    * ACCEPTED/DRAFTING duels whose draft never left the lobby (zero picks),
      `cutoff_hours` past their draft time — cancelled + all stakes refunded.

  Live drafts (any picks recorded) are never touched: long-clock async drafts
  legitimately run for days. Returns `%{pending: n, lobby: n}`.
  """
  def expire_stale(cutoff_hours \\ 24) do
    cutoff = DateTime.utc_now() |> DateTime.add(-cutoff_hours * 3600, :second)

    pending_ids =
      from(d in Duel, where: d.status == "pending" and d.draft_starts_at < ^cutoff, select: d.id)
      |> Repo.all()

    pending_count = Enum.count(pending_ids, fn id -> swept?(fn -> expire_pending(id) end) end)

    # Only drafts still sitting in the LOBBY count as dead — a zero-pick but
    # ACTIVE draft is a live long-clock game (24h first pick is legal), and
    # cancelling it would refund stakes for a duel the engine may yet finish.
    # Zero-picks is kept as a second belt: any board activity means life.
    lobby_ids =
      from(d in Duel,
        left_join: dr in HeadsUp.Drafts.Draft,
        on: dr.duel_id == d.id,
        left_join: pk in HeadsUp.Drafts.Pick,
        on: pk.draft_id == dr.id,
        where:
          d.status in ["accepted", "drafting"] and d.draft_starts_at < ^cutoff and
            (is_nil(dr.id) or dr.status == "lobby"),
        group_by: d.id,
        having: count(pk.id) == 0,
        select: d.id
      )
      |> Repo.all()

    lobby_count = Enum.count(lobby_ids, fn id -> swept?(fn -> cancel_drafting(id) end) end)

    %{pending: pending_count, lobby: lobby_count}
  end

  # One bad duel must not abort the whole sweep.
  defp swept?(fun) do
    match?({:ok, _}, fun.())
  rescue
    e ->
      require Logger
      Logger.error("expire_stale: sweep of one duel raised #{Exception.message(e)}")
      false
  end

  # Cancel one expired pending challenge; the challenger's stake rides home in
  # the same transaction. The UPDATE is status-guarded at the SQL level so a
  # concurrent accept/decline/counter wins the race cleanly — if the row is no
  # longer "pending" we touch nothing and refund nobody.
  defp expire_pending(duel_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:duel, fn repo, _ ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      from(d in Duel, where: d.id == ^duel_id and d.status == "pending", select: d)
      |> repo.update_all(set: [status: "cancelled", updated_at: now])
      |> case do
        {1, [fresh]} -> {:ok, fresh}
        {0, _} -> {:error, :already_resolved}
      end
    end)
    |> Ecto.Multi.run(:coins, fn repo, %{duel: fresh} -> refund_staked(repo, fresh) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{duel: fresh}} ->
        HeadsUp.Notifications.notify_user(
          fresh.challenger_id,
          "Challenge expired 🕰️",
          "Your #{String.upcase(fresh.sport)} challenge was never answered — your stake came home.",
          %{type: "duel", duel_id: fresh.id}
        )

        {:ok, fresh}

      {:error, _step, :already_resolved, _} ->
        {:error, :already_resolved}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  # Generic guarded status change: the duel must be at `from_status` and the
  # acting user must hold the given `role`. The status flip and its coin
  # movement commit (or fail) together.
  defp transition(%User{id: uid}, id, role, from_status, to_status) do
    duel = Repo.get(Duel, id)

    cond do
      is_nil(duel) ->
        {:error, :not_found}

      duel.status != from_status ->
        {:error, :not_found}

      role == :opponent and duel.opponent_id != uid ->
        {:error, :not_found}

      role == :challenger and duel.challenger_id != uid ->
        {:error, :not_found}

      true ->
        Ecto.Multi.new()
        |> Ecto.Multi.update(:duel, Duel.status_changeset(duel, to_status))
        |> Ecto.Multi.run(:coins, fn repo, %{duel: fresh} ->
          transition_coins(repo, fresh, uid, to_status)
        end)
        |> Repo.transaction()
        |> case do
          {:ok, %{duel: fresh}} -> {:ok, fresh} |> sync_seat(uid, to_status) |> with_users()
          {:error, _step, reason, _} -> {:error, reason}
        end
    end
  end

  # Accepting stakes the actor in; declining/cancelling refunds everyone who
  # staked. (The seat rows are still pristine here — sync_seat runs after —
  # so "who staked" is exactly the accepted seats.)
  defp transition_coins(repo, %Duel{} = duel, uid, "accepted"),
    do: Coins.stake(repo, uid, duel.id, duel.stake_coins)

  defp transition_coins(repo, %Duel{} = duel, _uid, to_status)
       when to_status in ["declined", "cancelled"],
       do: refund_staked(repo, duel)

  defp transition_coins(_repo, _duel, _uid, _to_status), do: {:ok, :noop}

  # Refund every staked player: stakes ride accepted seats (seat 0 auto-accepts
  # at creation, mirroring the challenger's stake; invitees stake on accept).
  defp refund_staked(_repo, %Duel{stake_coins: 0}), do: {:ok, :no_stake}

  defp refund_staked(repo, %Duel{} = duel) do
    staked =
      from(p in Participant,
        where: p.duel_id == ^duel.id and p.status == "accepted",
        select: p.user_id
      )
      |> repo.all()

    Enum.reduce_while(staked, {:ok, []}, fn uid, {:ok, acc} ->
      case Coins.refund(repo, uid, duel.id, duel.stake_coins) do
        {:ok, txn} -> {:cont, {:ok, [txn | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Coins that SHOULD be sitting in duel escrow right now: every live duel's
  stake summed once per staked (accepted-seat) player. The coin ledger's
  integrity check reconciles the escrow account against this.
  """
  def expected_escrow_coins do
    from(d in Duel,
      join: p in Participant,
      on: p.duel_id == d.id and p.status == "accepted",
      where: d.stake_coins > 0 and d.status in ["pending", "accepted", "drafting", "drafted"],
      select: coalesce(sum(d.stake_coins), 0)
    )
    |> Repo.one()
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
        # Seat answer + the actor's stake + any collapse-refunds are atomic: an
        # accept that can't cover the stake leaves the seat invited.
        Repo.transaction(fn ->
          {:ok, _} = seat |> Participant.changeset(%{status: new_status}) |> Repo.update()

          with {:ok, _} <- seat_coins(Repo, duel, actor, new_status),
               {:ok, fresh} <- resolve_group_status(duel, actor, new_status) do
            fresh
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
    end
  end

  defp seat_coins(repo, %Duel{} = duel, %User{id: uid}, "accepted"),
    do: Coins.stake(repo, uid, duel.id, duel.stake_coins)

  defp seat_coins(_repo, _duel, _actor, _new_status), do: {:ok, :noop}

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

    with {:ok, fresh} <- result,
         # A collapse sends everyone's stake home (the decliner never staked —
         # their seat already flipped, so they're not in the accepted set).
         {:ok, _} <-
           (if duel_status == "cancelled", do: refund_staked(Repo, fresh), else: {:ok, :noop}) do
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
