defmodule HeadsUp.Drafts do
  @moduledoc """
  The Drafts context: the durable side of the live draft engine. Owns the
  `drafts` + `draft_picks` rows and the pure snake-order / coin-flip helpers.

  The per-draft GenServer (`HeadsUp.Drafts.Server`) is the live source of truth;
  this context is how it persists picks (so a crash can replay them) and how the
  channel finds-or-creates the draft for a duel. Duel status transitions live in
  `Contests` (the sole writer of `Duel.status`); we delegate to it here so the
  duel flips accepted -> drafting -> drafted in lockstep with the draft.
  """
  import Ecto.Query, warn: false

  alias HeadsUp.Repo
  alias HeadsUp.Contests
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Sports.Player
  alias HeadsUp.Drafts.{Draft, Pick, Lineup}

  # --- draft rows ---------------------------------------------------------

  @doc "Fetch a draft by id (with the duel preloaded), or nil."
  def get_draft(id) do
    Draft |> Repo.get(id) |> Repo.preload(:duel)
  end

  @doc """
  Find the draft for an accepted duel, creating the lobby-phase row if needed.
  Race-safe: a duplicate insert (unique duel_id) falls back to the existing row,
  so two phones joining at once still converge on one draft.
  """
  def get_or_create_draft_for_duel(%Duel{} = duel) do
    case Repo.get_by(Draft, duel_id: duel.id) do
      %Draft{} = draft ->
        {:ok, Repo.preload(draft, :duel)}

      nil ->
        total = Lineup.slot_count(duel.lineup_template) * 2

        %Draft{}
        |> Draft.create_changeset(%{duel_id: duel.id, total_picks: total})
        |> Repo.insert()
        |> case do
          {:ok, draft} -> {:ok, Repo.preload(draft, :duel)}
          {:error, _} -> {:ok, Repo.get_by!(Draft, duel_id: duel.id) |> Repo.preload(:duel)}
        end
    end
  end

  @doc """
  Move a lobby draft to active: record the coin-flip winner (`first_picker_id`)
  and flip the duel accepted -> drafting, atomically.
  """
  def start_active(%Draft{} = draft, first_picker_id) do
    now = now()

    Ecto.Multi.new()
    |> Ecto.Multi.update(
      :draft,
      Draft.status_changeset(draft, %{
        status: "active",
        first_picker_id: first_picker_id,
        started_at: now,
        current_pick_number: 1
      })
    )
    |> Ecto.Multi.run(:duel, fn _repo, _ -> Contests.start_draft(draft.duel_id) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{draft: draft}} -> {:ok, draft}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Persist a single pick and advance the draft's `current_pick_number`, in one
  transaction. The unique (draft_id, player_id) index makes the shared board
  race-safe: a double-draft of the same player fails the changeset.
  """
  def record_pick(%{draft_id: draft_id, pick_number: pick_number} = attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:pick, Pick.changeset(%Pick{}, attrs))
    |> Ecto.Multi.update_all(
      :advance,
      from(d in Draft, where: d.id == ^draft_id),
      set: [current_pick_number: pick_number + 1, updated_at: now()]
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{pick: pick}} -> {:ok, pick}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc "Mark a draft complete and flip the duel drafting -> drafted."
  def complete_draft(draft_id) do
    now = now()

    Ecto.Multi.new()
    |> Ecto.Multi.run(:draft, fn repo, _ ->
      case repo.get(Draft, draft_id) do
        nil -> {:error, :not_found}
        draft -> repo.update(Draft.status_changeset(draft, %{status: "complete", completed_at: now}))
      end
    end)
    |> Ecto.Multi.run(:duel, fn _repo, %{draft: draft} -> Contests.finish_draft(draft.duel_id) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{draft: draft}} -> {:ok, draft}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Cancel a draft (no-show / abort) and return the duel to "cancelled". No
  forfeit win — nobody wins a ghosted draft (locked rule).
  """
  def cancel_draft(draft_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:draft, fn repo, _ ->
      case repo.get(Draft, draft_id) do
        nil -> {:error, :not_found}
        draft -> repo.update(Draft.status_changeset(draft, %{status: "cancelled"}))
      end
    end)
    |> Ecto.Multi.run(:duel, fn _repo, %{draft: draft} -> Contests.cancel_drafting(draft.duel_id) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{draft: draft}} -> {:ok, draft}
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  @doc "Ordered picks for crash-recovery replay."
  def replay(draft_id) do
    from(p in Pick,
      where: p.draft_id == ^draft_id,
      order_by: [asc: p.pick_number],
      select: %{
        pick_number: p.pick_number,
        user_id: p.user_id,
        player_id: p.player_id,
        slot: p.slot,
        auto_picked: p.auto_picked
      }
    )
    |> Repo.all()
  end

  @doc "The draftable pool for a sport as `%{player_id => player_map}` (with projection)."
  def draft_pool(sport) do
    from(p in Player,
      where: p.sport == ^sport,
      select: %{
        id: p.id,
        name: p.name,
        team: p.team,
        position: p.position,
        sport: p.sport,
        projection: p.projection
      }
    )
    |> Repo.all()
    |> Map.new(fn p -> {p.id, p} end)
  end

  # --- pure snake / coin-flip helpers (no DB; injectable rng for tests) ----

  @doc "Coin flip: returns the user_id who picks #1. `rng` is a 1-arity fun like `&:rand.uniform/1`."
  def coin_flip(challenger_id, opponent_id, rng \\ &:rand.uniform/1) do
    if rng.(2) == 1, do: challenger_id, else: opponent_id
  end

  @doc """
  Full snake pick sequence of user_ids for a 2-player draft. Round 1 =
  [first, other], round 2 = [other, first], ... Length == 2 * rounds == total
  picks; `pick_number` is a 1-based index into this list.
  """
  def build_pick_order(first_picker_id, other_id, rounds) do
    Enum.flat_map(1..rounds, fn round ->
      if rem(round, 2) == 1 do
        [first_picker_id, other_id]
      else
        [other_id, first_picker_id]
      end
    end)
  end

  @doc "Who is on the clock for a given 1-based pick number."
  def picker_for(pick_order, pick_number), do: Enum.at(pick_order, pick_number - 1)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
