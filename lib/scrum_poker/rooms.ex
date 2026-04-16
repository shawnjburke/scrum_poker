defmodule ScrumPoker.Rooms do
  @moduledoc """
  Context for managing rooms, tickets, votes, and participants.
  """

  import Ecto.Query, warn: false
  alias ScrumPoker.Repo
  alias ScrumPoker.Rooms.{Room, Ticket, Vote, RoomParticipant}

  # ---------------------------------------------------------------------------
  # Rooms
  # ---------------------------------------------------------------------------

  def get_room!(id), do: Repo.get!(Room, id)

  def get_room_by_code(code) do
    Repo.get_by(Room, code: String.upcase(code))
  end

  def get_room_by_code!(code) do
    Repo.get_by!(Room, code: String.upcase(code))
  end

  def get_room_with_details!(code) do
    Room
    |> Repo.get_by!(code: String.upcase(code))
    |> Repo.preload([:scrum_master, tickets: [:votes], participants: [:user]])
  end

  def create_room(attrs, scrum_master) do
    %Room{}
    |> Room.changeset(Map.put(attrs, "scrum_master_id", scrum_master.id))
    |> Repo.insert()
  end

  def update_room_status(%Room{} = room, status) do
    room
    |> Room.status_changeset(status)
    |> Repo.update()
  end

  def list_rooms_for_user(user_id) do
    Room
    |> where([r], r.scrum_master_id == ^user_id)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Tickets
  # ---------------------------------------------------------------------------

  def get_ticket!(id), do: Repo.get!(Ticket, id)

  def add_ticket(room, attrs) do
    position = next_ticket_position(room.id)

    %Ticket{}
    |> Ticket.changeset(Map.merge(attrs, %{"room_id" => room.id, "position" => position}))
    |> Repo.insert()
  end

  def update_ticket_status(%Ticket{} = ticket, status) do
    ticket
    |> Ticket.status_changeset(status)
    |> Repo.update()
  end

  def accept_ticket(%Ticket{} = ticket, points) do
    ticket
    |> Ticket.accept_changeset(points)
    |> Repo.update()
  end

  def list_accepted_tickets(room_id) do
    Ticket
    |> where([t], t.room_id == ^room_id and t.status == "accepted")
    |> order_by([t], asc: t.position)
    |> Repo.all()
  end

  defp next_ticket_position(room_id) do
    Ticket
    |> where([t], t.room_id == ^room_id)
    |> select([t], count(t.id))
    |> Repo.one()
  end

  # ---------------------------------------------------------------------------
  # Votes
  # ---------------------------------------------------------------------------

  def cast_vote(ticket, value, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    guest_token = Keyword.get(opts, :guest_token)
    guest_name = Keyword.get(opts, :guest_name)

    attrs = %{
      "ticket_id" => ticket.id,
      "value" => value,
      "user_id" => user_id,
      "guest_token" => guest_token,
      "guest_name" => guest_name
    }

    case existing_vote(ticket.id, user_id, guest_token) do
      nil ->
        %Vote{}
        |> Vote.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Vote.changeset(attrs)
        |> Repo.update()
    end
  end

  def get_votes_for_ticket(ticket_id) do
    Vote
    |> where([v], v.ticket_id == ^ticket_id)
    |> preload(:user)
    |> Repo.all()
  end

  defp existing_vote(ticket_id, user_id, guest_token) do
    cond do
      user_id ->
        Repo.get_by(Vote, ticket_id: ticket_id, user_id: user_id)

      guest_token ->
        Repo.get_by(Vote, ticket_id: ticket_id, guest_token: guest_token)

      true ->
        nil
    end
  end

  # ---------------------------------------------------------------------------
  # Participants
  # ---------------------------------------------------------------------------

  def join_room(room, opts \\ []) do
    user = Keyword.get(opts, :user)
    guest_name = Keyword.get(opts, :guest_name)
    guest_token = Keyword.get(opts, :guest_token)
    role = Keyword.get(opts, :role, "voter")

    attrs = %{
      "room_id" => room.id,
      "role" => role,
      "user_id" => user && user.id,
      "guest_name" => guest_name,
      "guest_token" => guest_token
    }

    case existing_participant(room.id, user && user.id, guest_token) do
      nil ->
        %RoomParticipant{}
        |> RoomParticipant.changeset(attrs)
        |> Repo.insert()

      existing ->
        {:ok, existing}
    end
  end

  def get_participants(room_id) do
    RoomParticipant
    |> where([p], p.room_id == ^room_id)
    |> preload(:user)
    |> Repo.all()
  end

  defp existing_participant(room_id, user_id, guest_token) do
    cond do
      user_id ->
        Repo.get_by(RoomParticipant, room_id: room_id, user_id: user_id)

      guest_token ->
        Repo.get_by(RoomParticipant, room_id: room_id, guest_token: guest_token)

      true ->
        nil
    end
  end
end
