defmodule HeadsUp.Repo.Migrations.RenameWagerCentsToStakeCoins do
  use Ecto.Migration

  # The vestigial wager_cents field becomes the duel's coin stake: the uniform
  # amount every player escrows to enter (0 = friendly).
  def change do
    rename table(:duels), :wager_cents, to: :stake_coins
  end
end
