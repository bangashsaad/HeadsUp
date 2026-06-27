defmodule HeadsUp.Settlement.Result do
  @moduledoc """
  The persisted outcome of a settled duel (1:1 with a duel): both team totals,
  the winner (nil = tie), and a frozen role-keyed per-player breakdown for the
  scoreboard. The unique index on duel_id is the DB-level double-settle guard.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias HeadsUp.Accounts.User
  alias HeadsUp.Contests.Duel

  schema "settlement_results" do
    field :is_tie, :boolean, default: false
    field :challenger_points, :float
    field :opponent_points, :float
    field :settled_at, :utc_datetime
    field :breakdown, :map

    belongs_to :duel, Duel
    belongs_to :winner, User

    timestamps(type: :utc_datetime)
  end

  def changeset(result, attrs) do
    result
    |> cast(attrs, [
      :duel_id,
      :winner_id,
      :is_tie,
      :challenger_points,
      :opponent_points,
      :settled_at,
      :breakdown
    ])
    |> validate_required([:duel_id, :challenger_points, :opponent_points, :settled_at])
    |> unique_constraint(:duel_id)
    |> foreign_key_constraint(:duel_id)
    |> foreign_key_constraint(:winner_id)
  end
end
