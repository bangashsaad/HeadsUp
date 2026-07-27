defmodule HeadsUp.Drafts.Draft do
  @moduledoc """
  A live draft, one per accepted duel. Holds the durable draft state that the
  per-draft GenServer hydrates from and writes back to, so a crash/restart can
  rebuild by replaying persisted picks.

  Status: `lobby` (ready-check) -> `active` (clock running) -> `complete`,
  or `cancelled` (no-show / aborted; no forfeit win — settlement is Phase 5).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias HeadsUp.Accounts.User
  alias HeadsUp.Contests.Duel
  alias HeadsUp.Drafts.Pick

  @statuses ~w(lobby active complete cancelled)

  schema "drafts" do
    field :status, :string, default: "lobby"
    field :current_pick_number, :integer, default: 1
    field :total_picks, :integer
    field :clock_deadline, :utc_datetime
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    # Round-1 order of the snake (user_ids). Persisted so an N-player draft can
    # rebuild its exact sequence on crash-replay; first_picker_id == hd(order).
    field :pick_order, {:array, :integer}

    belongs_to :duel, Duel
    belongs_to :first_picker, User
    has_many :picks, Pick

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating the (lobby-phase) draft row for a duel."
  def create_changeset(draft, attrs) do
    draft
    |> cast(attrs, [:duel_id, :total_picks, :status, :current_pick_number])
    |> validate_required([:duel_id, :total_picks])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:duel_id)
    |> foreign_key_constraint(:duel_id)
  end

  @doc "Changeset for advancing draft state (coin flip, clock, completion)."
  def status_changeset(draft, attrs) do
    draft
    |> cast(attrs, [
      :status,
      :current_pick_number,
      :clock_deadline,
      :started_at,
      :completed_at,
      :first_picker_id,
      :pick_order
    ])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:first_picker_id)
  end

  def statuses, do: @statuses
end
