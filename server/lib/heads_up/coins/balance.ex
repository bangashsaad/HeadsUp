defmodule HeadsUp.Coins.Balance do
  @moduledoc """
  Cached signed balance per account. `coin_entries` is the truth; this is the
  read model, re-derived and checked by `HeadsUp.Coins.Integrity`.
  """
  use Ecto.Schema

  @primary_key false

  @type t :: %__MODULE__{}

  schema "coin_balances" do
    belongs_to :account, HeadsUp.Coins.Account, primary_key: true
    field :amount, :integer, default: 0
    field :entry_count, :integer, default: 0

    timestamps(type: :utc_datetime, inserted_at: false)
  end
end
