defmodule ScrumPoker.Rooms.RoomParticipant do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_roles ~w(scrum_master voter observer)

  schema "room_participants" do
    field :guest_name, :string
    field :guest_token, :string
    field :role, :string, default: "voter"

    belongs_to :room, ScrumPoker.Rooms.Room
    belongs_to :user, ScrumPoker.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:guest_name, :guest_token, :role, :room_id, :user_id])
    |> validate_required([:role, :room_id])
    |> validate_inclusion(:role, @valid_roles)
    |> unique_constraint([:room_id, :user_id])
    |> unique_constraint([:room_id, :guest_token])
  end

  def display_name(%__MODULE__{user: %ScrumPoker.Accounts.User{} = user}) do
    user.display_name || user.email
  end

  def display_name(%__MODULE__{guest_name: name}) when is_binary(name), do: name
  def display_name(_), do: "Anonymous"
end
