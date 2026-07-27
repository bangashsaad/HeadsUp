defmodule HeadsUp.Social.Friendship do
  use Ecto.Schema
  import Ecto.Changeset

  alias HeadsUp.Accounts.User

  @statuses ~w(pending accepted)

  schema "friendships" do
    field :status, :string, default: "pending"

    belongs_to :requester, User
    belongs_to :addressee, User

    timestamps(type: :utc_datetime)
  end

  def changeset(friendship, attrs) do
    friendship
    |> cast(attrs, [:requester_id, :addressee_id, :status])
    |> validate_required([:requester_id, :addressee_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:requester_id)
    |> foreign_key_constraint(:addressee_id)
    |> unique_constraint([:requester_id, :addressee_id],
      message: "friend request already exists"
    )
    |> check_constraint(:requester_id,
      name: :requester_not_addressee,
      message: "you can't friend yourself"
    )
  end
end
