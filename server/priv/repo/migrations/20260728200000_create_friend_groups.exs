defmodule HeadsUp.Repo.Migrations.CreateFriendGroups do
  use Ecto.Migration

  def change do
    create table(:friend_groups) do
      # Groups are PRIVATE to their owner — your "CREW" is your label for
      # those people; they never see it and can't be in it twice.
      add :owner_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create index(:friend_groups, [:owner_id])
    create unique_index(:friend_groups, [:owner_id, :name])

    create table(:friend_group_members) do
      add :group_id, references(:friend_groups, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:friend_group_members, [:group_id, :user_id])
    create index(:friend_group_members, [:user_id])
  end
end
