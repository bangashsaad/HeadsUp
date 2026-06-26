defmodule HeadsUp.Contests.Duel do
  use Ecto.Schema
  import Ecto.Changeset

  alias HeadsUp.Accounts.User

  @sports ~w(nfl nba mlb)
  @draft_types ~w(snake auction)
  @statuses ~w(pending accepted declined countered cancelled)

  schema "duels" do
    field :sport, :string
    field :draft_type, :string, default: "snake"
    field :roster_size, :integer
    field :scoring_rules, :map
    field :wager_cents, :integer, default: 0
    field :draft_starts_at, :utc_datetime
    field :status, :string, default: "pending"

    belongs_to :challenger, User
    belongs_to :opponent, User
    belongs_to :parent_duel, __MODULE__, foreign_key: :parent_duel_id

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating a duel (a challenge or a counter-offer)."
  def create_changeset(duel, attrs) do
    duel
    |> cast(attrs, [
      :sport,
      :draft_type,
      :roster_size,
      :scoring_rules,
      :wager_cents,
      :draft_starts_at,
      :status,
      :challenger_id,
      :opponent_id,
      :parent_duel_id
    ])
    |> validate_required([
      :sport,
      :draft_type,
      :roster_size,
      :scoring_rules,
      :draft_starts_at,
      :status,
      :challenger_id,
      :opponent_id
    ])
    |> validate_inclusion(:sport, @sports)
    |> validate_inclusion(:draft_type, @draft_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:roster_size, greater_than_or_equal_to: 1, less_than_or_equal_to: 15)
    |> validate_number(:wager_cents, greater_than_or_equal_to: 0)
    |> validate_future_draft()
    |> foreign_key_constraint(:challenger_id)
    |> foreign_key_constraint(:opponent_id)
    |> check_constraint(:opponent_id,
      name: :challenger_not_opponent,
      message: "you can't challenge yourself"
    )
  end

  @doc "Changeset for moving a duel to a new status."
  def status_changeset(duel, status) do
    duel
    |> change(status: status)
    |> validate_inclusion(:status, @statuses)
  end

  defp validate_future_draft(changeset) do
    validate_change(changeset, :draft_starts_at, fn :draft_starts_at, draft_starts_at ->
      if DateTime.compare(draft_starts_at, DateTime.utc_now()) == :gt do
        []
      else
        [draft_starts_at: "must be in the future"]
      end
    end)
  end
end
