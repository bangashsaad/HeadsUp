defmodule HeadsUp.Social.FriendGroupMember do
  @moduledoc "Join row: one friend inside one of the owner's groups."
  use Ecto.Schema

  import Ecto.Changeset

  schema "friend_group_members" do
    belongs_to :group, HeadsUp.Social.FriendGroup
    belongs_to :user, HeadsUp.Accounts.User
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:group_id, :user_id])
    |> validate_required([:group_id, :user_id])
    |> unique_constraint([:group_id, :user_id])
    |> foreign_key_constraint(:group_id)
    |> foreign_key_constraint(:user_id)
  end
end
