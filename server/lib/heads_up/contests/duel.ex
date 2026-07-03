defmodule HeadsUp.Contests.Duel do
  use Ecto.Schema
  import Ecto.Changeset

  alias HeadsUp.Accounts.User
  alias HeadsUp.Contests.Scoring
  alias HeadsUp.Drafts.Lineup

  @type t :: %__MODULE__{}

  @sports ~w(nfl nba mlb wnba)
  @draft_types ~w(snake auction)
  # drafting = live draft underway; drafted = draft done, awaiting scoring;
  # settled = stats totaled, winner declared (Phase 5).
  @statuses ~w(pending accepted declined countered cancelled drafting drafted settled)
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

    # Scoring window (frozen when the draft finishes) + denormalized settlement
    # outcome (winner_id nil + status "settled" == a tie). Full per-player
    # breakdown + scores live in settlement_results.
    field :scoring_window_start, :utc_datetime
    field :scoring_window_end, :utc_datetime
    field :settled_at, :utc_datetime

    belongs_to :challenger, User
    belongs_to :opponent, User
    belongs_to :winner, User
    belongs_to :parent_duel, __MODULE__, foreign_key: :parent_duel_id
    has_many :participants, HeadsUp.Contests.Participant, preload_order: [asc: :seat]

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
    |> validate_scoring_rules()
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

  @doc "Changeset for finishing the draft: flips to a status and freezes the scoring window."
  def finish_changeset(duel, attrs) do
    duel
    |> cast(attrs, [:status, :scoring_window_start, :scoring_window_end])
    |> validate_inclusion(:status, @statuses)
  end

  @doc "Changeset recording the settled outcome (winner_id nil => tie). Status -> settled."
  def settle_changeset(duel, attrs) do
    duel
    |> cast(attrs, [:status, :winner_id, :settled_at])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:winner_id)
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

  # The frozen scoring chart must be non-empty, use only known categories for the
  # sport, and have numeric weights — so settlement can never crash on a string
  # weight or silently tie on an empty/unknown-key chart.
  defp validate_scoring_rules(changeset) do
    sport = get_field(changeset, :sport)
    rules = get_field(changeset, :scoring_rules)

    cond do
      not is_map(rules) or map_size(rules) == 0 ->
        add_error(changeset, :scoring_rules, "can't be empty")

      not is_binary(sport) ->
        changeset

      true ->
        valid_keys = sport |> Scoring.default_rules() |> Map.keys() |> MapSet.new()

        cond do
          bad = Enum.find(Map.keys(rules), &(not MapSet.member?(valid_keys, &1))) ->
            add_error(changeset, :scoring_rules, "has an unknown category: #{bad}")

          not Enum.all?(Map.values(rules), &is_number/1) ->
            add_error(changeset, :scoring_rules, "weights must be numbers")

          true ->
            changeset
        end
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
