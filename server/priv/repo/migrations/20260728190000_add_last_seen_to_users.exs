defmodule HeadsUp.Repo.Migrations.AddLastSeenToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Stamped (throttled) on authenticated requests. Powers the "online"
      # dot without holding a socket open — see HeadsUpWeb.UserAuth.
      add :last_seen_at, :utc_datetime
    end
  end
end
