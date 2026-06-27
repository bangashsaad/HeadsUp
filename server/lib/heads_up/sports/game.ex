defmodule HeadsUp.Sports.Game do
  use Ecto.Schema
  import Ecto.Changeset

  @sports ~w(nfl nba mlb wnba)
  @statuses ~w(scheduled live final)

  schema "games" do
    field :sport, :string
    field :external_id, :string
    field :home_team, :string
    field :away_team, :string
    field :starts_at, :utc_datetime
    field :status, :string, default: "scheduled"

    timestamps(type: :utc_datetime)
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [:sport, :external_id, :home_team, :away_team, :starts_at, :status])
    |> validate_required([:sport, :external_id, :home_team, :away_team, :status])
    |> validate_inclusion(:sport, @sports)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:sport, :external_id])
  end
end
