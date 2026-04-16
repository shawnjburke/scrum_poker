defmodule ScrumPoker.Repo.Migrations.CreateTickets do
  use Ecto.Migration

  def change do
    create table(:tickets) do
      add :room_id, references(:rooms, on_delete: :delete_all), null: false
      add :external_id, :string
      add :title, :string, null: false
      add :description, :text
      add :url, :string
      add :status, :string, null: false, default: "pending"
      add :final_points, :string
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:tickets, [:room_id])
    create index(:tickets, [:room_id, :position])
  end
end
