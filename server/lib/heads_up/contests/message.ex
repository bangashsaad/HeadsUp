defmodule HeadsUp.Contests.Message do
  @moduledoc """
  One line of trash talk in a duel's thread.

  280 characters — a jab, not an essay. The thread lives on the duel so the
  receipts survive settlement; a rivalry's history is the product.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "duel_messages" do
    field :body, :string

    belongs_to :duel, HeadsUp.Contests.Duel
    belongs_to :user, HeadsUp.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: 280)
  end
end
