defmodule ScrumPoker.Repo.Migrations.CreateRoomParticipants do
  use Ecto.Migration

  def change do
    create table(:room_participants) do
      add :room_id, references(:rooms, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :guest_name, :string
      add :guest_token, :string
      add :role, :string, null: false, default: "voter"

      timestamps(type: :utc_datetime)
    end

    create index(:room_participants, [:room_id])
    create unique_index(:room_participants, [:room_id, :user_id], where: "user_id IS NOT NULL")
    create unique_index(:room_participants, [:room_id, :guest_token],
             where: "guest_token IS NOT NULL"
           )
  end
end
