defmodule HeadsUp.Coins.Entry do
  @moduledoc """
  One leg of a coin transaction. Amounts are signed integers: debits positive,
  credits negative. Append-only — the database raises on UPDATE/DELETE.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "coin_entries" do
    belongs_to :txn, HeadsUp.Coins.Txn
    belongs_to :account, HeadsUp.Coins.Account
    field :amount, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:txn_id, :account_id, :amount])
    |> validate_required([:txn_id, :account_id, :amount])
    |> check_constraint(:amount, name: :amount_nonzero)
  end
end
