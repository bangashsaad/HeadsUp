defmodule HeadsUp.Coins.Account do
  @moduledoc """
  A coin ledger account: system accounts have a unique `code` ("mint",
  "escrow.duels"), user wallets have a unique `owner_user_id`. Exactly one of
  the two is set (DB check constraint).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  # Wallets/liabilities/income are credit-normal (their natural balance is the
  # NEGATED signed sum); assets ("mint") are debit-normal.
  @kinds ~w(wallet asset liability income)
  @credit_normal ~w(wallet liability income)

  schema "coin_accounts" do
    field :code, :string
    field :kind, :string
    belongs_to :owner_user, HeadsUp.Accounts.User, foreign_key: :owner_user_id

    timestamps(type: :utc_datetime)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:code, :kind, :owner_user_id])
    |> validate_required([:kind])
    |> validate_inclusion(:kind, @kinds)
    |> check_constraint(:code, name: :code_or_owner_required)
    |> unique_constraint(:code)
    |> unique_constraint(:owner_user_id)
    |> foreign_key_constraint(:owner_user_id)
  end

  @doc "Whether the account's natural balance grows with credits (negative entries)."
  @spec credit_normal?(t()) :: boolean()
  def credit_normal?(%__MODULE__{kind: kind}), do: kind in @credit_normal
end
