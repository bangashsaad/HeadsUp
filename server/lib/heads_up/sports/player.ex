defmodule HeadsUp.Sports.Player do
  use Ecto.Schema
  import Ecto.Changeset

  @sports ~w(nfl nba mlb wnba)

  schema "players" do
    field :sport, :string
    field :external_id, :string
    field :name, :string
    field :team, :string
    field :position, :string
    field :projection, :float, default: 0.0

    timestamps(type: :utc_datetime)
  end

  def changeset(player, attrs) do
    player
    |> cast(attrs, [:sport, :external_id, :name, :team, :position, :projection])
    |> validate_required([:sport, :external_id, :name])
    |> validate_inclusion(:sport, @sports)
    |> unique_constraint([:sport, :external_id])
  end
end
