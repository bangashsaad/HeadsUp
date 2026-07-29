defmodule HeadsUp.Social.FriendGroup do
  @moduledoc """
  A private, user-named bucket of friends ("CREW", "WORK") used to filter the
  challenge screen's recipient list. Owned by one user and invisible to the
  people inside it; a friend may belong to several groups.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @name_max 20

  schema "friend_groups" do
    field :name, :string
    belongs_to :owner, HeadsUp.Accounts.User, foreign_key: :owner_id
    has_many :members, HeadsUp.Social.FriendGroupMember, foreign_key: :group_id
    timestamps(type: :utc_datetime)
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :owner_id])
    |> update_change(:name, &normalize/1)
    |> validate_required([:name, :owner_id])
    |> validate_length(:name, min: 1, max: @name_max)
    |> unique_constraint([:owner_id, :name], message: "you already have a group with that name")
    |> foreign_key_constraint(:owner_id)
  end

  def name_max, do: @name_max

  # Tabs render uppercase; store trimmed + collapsed so "  my  crew " and
  # "My Crew" can't become two different groups.
  defp normalize(name) when is_binary(name),
    do: name |> String.trim() |> String.replace(~r/\s+/, " ")

  defp normalize(other), do: other
end
