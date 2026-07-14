defmodule HeadsUp.Repo.Migrations.AddSlateDateToDuels do
  use Ecto.Migration

  def change do
    alter table(:duels) do
      # The ET calendar day this duel's games come from. NULL = legacy duel
      # (window anchored at draft completion, pool spans today+tomorrow).
      add :slate_date, :date
    end
  end
end
