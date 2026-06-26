defmodule HeadsUp.Repo.Migrations.CreateFriendships do
  use Ecto.Migration

  def change do
    create table(:friendships) do
      # requester = who sent the request, addressee = who received it
      add :requester_id, references(:users, on_delete: :delete_all), null: false
      add :addressee_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, null: false, default: "pending"
      timestamps(type: :utc_datetime)
    end

    # Only one friendship row per ordered pair.
    create unique_index(:friendships, [:requester_id, :addressee_id])
    # Fast lookups of "requests sent to me".
    create index(:friendships, [:addressee_id])
    # You can't friend yourself.
    create constraint(:friendships, :requester_not_addressee, check: "requester_id <> addressee_id")
  end
end
