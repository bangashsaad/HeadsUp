defmodule HeadsUp.Drafts.Pick do
  @moduledoc """
  One pick in a draft: which user took which player, the global 1-indexed pick
  number, and the assigned lineup slot key (from `HeadsUp.Drafts.Lineup`).
  Persisted on every pick so draft state is replayable after a crash.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias HeadsUp.Accounts.User
  alias HeadsUp.Drafts.Draft
  alias HeadsUp.Sports.Player

  schema "draft_picks" do
    field :pick_number, :integer
    field :slot, :string
    field :auto_picked, :boolean, default: false

    belongs_to :draft, Draft
    belongs_to :user, User
    belongs_to :player, Player

    timestamps(type: :utc_datetime)
  end

  def changeset(pick, attrs) do
    pick
    |> cast(attrs, [:draft_id, :user_id, :player_id, :pick_number, :slot, :auto_picked])
    |> validate_required([:draft_id, :user_id, :player_id, :pick_number, :slot])
    |> unique_constraint([:draft_id, :pick_number])
    |> unique_constraint([:draft_id, :player_id])
    |> foreign_key_constraint(:player_id)
  end
end
