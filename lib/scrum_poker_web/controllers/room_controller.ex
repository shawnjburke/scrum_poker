defmodule ScrumPokerWeb.RoomController do
  use ScrumPokerWeb, :controller

  alias ScrumPoker.Rooms

  @doc """
  Handles guest join POST. Sets the guest token and name in the session,
  then redirects to the room.
  """
  def join(conn, %{"code" => code, "participant" => %{"name" => name}}) do
    name = String.trim(name)
    code = String.upcase(code)

    case Rooms.get_room_by_code(code) do
      nil ->
        conn
        |> put_flash(:error, "Room not found.")
        |> redirect(to: ~p"/")

      room ->
        guest_token = generate_token()

        case Rooms.join_room(room, guest_name: name, guest_token: guest_token, role: "voter") do
          {:ok, _participant} ->
            conn
            |> put_session(:guest_token, guest_token)
            |> put_session(:guest_name, name)
            |> redirect(to: ~p"/rooms/#{code}")

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Could not join room. Please try again.")
            |> redirect(to: ~p"/rooms/#{code}/join")
        end
    end
  end

  def join(conn, %{"code" => code}) do
    conn
    |> put_flash(:error, "Please enter a display name.")
    |> redirect(to: ~p"/rooms/#{code}/join")
  end

  defp generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
