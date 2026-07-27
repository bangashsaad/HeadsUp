defmodule HeadsUp.Contests.Participant do
  @moduledoc """
  One player's seat in a contest. Seat 0 is the host (created accepted); seats
  1..3 are invitees who accept or decline independently. A duel is draftable
  when every non-declined seat has accepted (and ≥ 2 players remain).

  For 1v1 duels this table shadows challenger/opponent — those columns stay
  the source of truth until the multiplayer engine lands.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias HeadsUp.Accounts.User
  alias HeadsUp.Contests.Duel

  @statuses ~w(invited accepted declined)
  @max_seat 3

  schema "duel_participants" do
    field :seat, :integer
    field :status, :string, default: "invited"

    belongs_to :duel, Duel
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def max_seat, do: @max_seat

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:duel_id, :user_id, :seat, :status])
    |> validate_required([:duel_id, :user_id, :seat, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:seat, greater_than_or_equal_to: 0, less_than_or_equal_to: @max_seat)
    |> unique_constraint([:duel_id, :user_id])
    |> unique_constraint([:duel_id, :seat])
    |> foreign_key_constraint(:duel_id)
    |> foreign_key_constraint(:user_id)
  end
end
