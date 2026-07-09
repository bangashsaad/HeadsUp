defmodule HeadsUp.Coins.Txn do
  @moduledoc """
  An append-only, balanced group of coin entries. Product movements carry an
  `idempotency_key` (e.g. "duel:42:settle") so a replay returns the original
  transaction instead of moving coins twice.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @kinds ~w(grant stake refund payout burn reversal)

  schema "coin_txns" do
    field :kind, :string
    field :idempotency_key, :string
    field :metadata, :map, default: %{}

    has_many :entries, HeadsUp.Coins.Entry, foreign_key: :txn_id, preload_order: [asc: :id]

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  def changeset(txn, attrs) do
    txn
    |> cast(attrs, [:kind, :idempotency_key, :metadata])
    |> validate_required([:kind])
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint(:idempotency_key)
  end
end
