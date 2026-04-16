defmodule ScrumPoker.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms) do
      add :code, :string, null: false
      add :name, :string, null: false
      add :status, :string, null: false, default: "waiting"
      add :card_deck, :string, null: false, default: "fibonacci"
      add :scrum_master_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:rooms, [:code])
    create index(:rooms, [:scrum_master_id])
  end
end
