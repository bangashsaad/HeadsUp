defmodule HeadsUp.Social.Block do
  @moduledoc """
  One user blocking another. Blocking is SYMMETRIC in effect: neither side can
  find, friend, or challenge the other, regardless of who blocked whom. The
  blocked user is never told.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "blocks" do
    belongs_to :blocker, HeadsUp.Accounts.User
    belongs_to :blocked, HeadsUp.Accounts.User
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(block, attrs) do
    block
    |> cast(attrs, [:blocker_id, :blocked_id])
    |> validate_required([:blocker_id, :blocked_id])
    |> check_blocker_is_not_blocked()
    |> unique_constraint([:blocker_id, :blocked_id])
    |> foreign_key_constraint(:blocker_id)
    |> foreign_key_constraint(:blocked_id)
  end

  defp check_blocker_is_not_blocked(changeset) do
    if get_field(changeset, :blocker_id) == get_field(changeset, :blocked_id) do
      add_error(changeset, :blocked_id, "you can't block yourself")
    else
      changeset
    end
  end
end
