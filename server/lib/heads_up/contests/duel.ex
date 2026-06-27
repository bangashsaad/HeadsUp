defmodule HeadsUp.Contests.Duel do
  use Ecto.Schema
  import Ecto.Changeset

  alias HeadsUp.Accounts.User
  alias HeadsUp.Drafts.Lineup

  @sports ~w(nfl nba mlb wnba)
  @draft_types ~w(snake auction)
  # drafting = live draft underway; drafted = draft done, awaiting Phase 5 scoring.
  @statuses ~w(pending accepted declined countered cancelled drafting drafted)
  @pick_clocks [30, 60, 90, 14_400, 43_200, 86_400]

  schema "duels" do
    field :sport, :string
    field :draft_type, :string, default: "snake"
    field :roster_size, :integer
    field :scoring_rules, :map
    field :wager_cents, :integer, default: 0
    field :draft_starts_at, :utc_datetime
    field :pick_clock_seconds, :integer, default: 60
    field :lineup_template, :string
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
      :pick_clock_seconds,
      :lineup_template,
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
      :pick_clock_seconds,
      :lineup_template,
      :status,
      :challenger_id,
      :opponent_id
    ])
    |> validate_inclusion(:sport, @sports)
    |> validate_inclusion(:draft_type, @draft_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:pick_clock_seconds, @pick_clocks)
    |> validate_inclusion(:lineup_template, Lineup.templates())
    |> validate_number(:roster_size, greater_than_or_equal_to: 1, less_than_or_equal_to: 15)
    |> validate_number(:wager_cents, greater_than_or_equal_to: 0)
    |> validate_lineup_for_sport()
    |> validate_roster_matches_template()
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

  # The lineup template must belong to the duel's sport (e.g. an nfl duel can't
  # use "nba_standard"). Only checked once both fields are present + valid.
  defp validate_lineup_for_sport(changeset) do
    sport = get_field(changeset, :sport)
    template = get_field(changeset, :lineup_template)

    if is_binary(sport) and is_binary(template) and Lineup.valid?(template) and
         not String.starts_with?(template, sport <> "_") do
      add_error(changeset, :lineup_template, "doesn't match the sport")
    else
      changeset
    end
  end

  # roster_size is server-derived from the template (Contests.build_attrs); this
  # guards against any mismatch so each team fills exactly its lineup.
  defp validate_roster_matches_template(changeset) do
    template = get_field(changeset, :lineup_template)
    roster_size = get_field(changeset, :roster_size)

    if is_binary(template) and Lineup.valid?(template) and
         roster_size != Lineup.slot_count(template) do
      add_error(changeset, :roster_size, "must match the lineup template")
    else
      changeset
    end
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
