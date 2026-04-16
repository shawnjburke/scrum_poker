defmodule ScrumPoker.Rooms.Ticket do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_statuses ~w(pending voting revealed accepted)

  schema "tickets" do
    field :external_id, :string
    field :title, :string
    field :description, :string
    field :url, :string
    field :status, :string, default: "pending"
    field :final_points, :string
    field :position, :integer, default: 0

    belongs_to :room, ScrumPoker.Rooms.Room
    has_many :votes, ScrumPoker.Rooms.Vote

    timestamps(type: :utc_datetime)
  end

  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [:external_id, :title, :description, :url, :room_id, :position])
    |> validate_required([:title, :room_id])
    |> validate_length(:title, max: 255)
  end

  def status_changeset(ticket, status) when status in @valid_statuses do
    change(ticket, status: status)
  end

  def accept_changeset(ticket, points) do
    change(ticket, status: "accepted", final_points: points)
  end
end
