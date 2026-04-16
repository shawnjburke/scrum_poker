defmodule ScrumPoker.Rooms.Vote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "votes" do
    field :value, :string
    field :guest_token, :string
    field :guest_name, :string

    belongs_to :ticket, ScrumPoker.Rooms.Ticket
    belongs_to :user, ScrumPoker.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:value, :guest_token, :guest_name, :ticket_id, :user_id])
    |> validate_required([:value, :ticket_id])
    |> validate_length(:value, max: 10)
    |> unique_constraint([:ticket_id, :user_id])
    |> unique_constraint([:ticket_id, :guest_token])
  end
end
