defmodule ScrumPoker.Repo.Migrations.CreateVotes do
  use Ecto.Migration

  def change do
    create table(:votes) do
      add :ticket_id, references(:tickets, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :guest_token, :string
      add :guest_name, :string
      add :value, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:votes, [:ticket_id])
    create unique_index(:votes, [:ticket_id, :user_id], where: "user_id IS NOT NULL")
    create unique_index(:votes, [:ticket_id, :guest_token], where: "guest_token IS NOT NULL")
  end
end
