defmodule ScrumPoker.Rooms.Room do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_statuses ~w(waiting voting revealed concluded)
  @valid_decks ~w(fibonacci modified_fibonacci tshirt)

  schema "rooms" do
    field :code, :string
    field :name, :string
    field :status, :string, default: "waiting"
    field :card_deck, :string, default: "fibonacci"

    belongs_to :scrum_master, ScrumPoker.Accounts.User
    has_many :tickets, ScrumPoker.Rooms.Ticket, preload_order: [asc: :position]
    has_many :participants, ScrumPoker.Rooms.RoomParticipant

    timestamps(type: :utc_datetime)
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :status, :card_deck, :scrum_master_id])
    |> validate_required([:name, :scrum_master_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:card_deck, @valid_decks)
    |> maybe_put_code()
  end

  def status_changeset(room, status) when status in @valid_statuses do
    change(room, status: status)
  end

  defp maybe_put_code(changeset) do
    if get_field(changeset, :code) do
      changeset
    else
      put_change(changeset, :code, generate_code())
    end
  end

  defp generate_code do
    :crypto.strong_rand_bytes(3)
    |> Base.encode16()
    |> String.upcase()
  end

  def card_values("fibonacci"), do: ~w(0 1 2 3 5 8 13 21 40 100 ? ☕)
  def card_values("modified_fibonacci"), do: ~w(0 ½ 1 2 3 5 8 13 20 40 100 ? ☕)
  def card_values("tshirt"), do: ~w(XS S M L XL XXL ? ☕)
  def card_values(_), do: card_values("fibonacci")
end
