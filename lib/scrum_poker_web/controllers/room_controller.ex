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

  @doc """
  Exports the session history as a CSV download.
  """
  def export_csv(conn, %{"code" => code}) do
    code = String.upcase(code)

    case Rooms.get_room_by_code(code) do
      nil ->
        conn
        |> put_flash(:error, "Room not found.")
        |> redirect(to: ~p"/")

      room ->
        tickets = Rooms.list_accepted_tickets(room.id)

        csv =
          [["Ticket ID", "Title", "Story Points", "Accepted At"]]
          |> Enum.concat(
            Enum.map(tickets, fn t ->
              [t.external_id || "", t.title, t.final_points || "", format_datetime(t.updated_at)]
            end)
          )
          |> Enum.map(&Enum.join(&1, ","))
          |> Enum.join("\r\n")

        filename = "#{room.name |> String.replace(~r/[^a-zA-Z0-9_\- ]/, "") |> String.trim()}_history.csv"

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> send_resp(200, csv)
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp format_datetime(nil), do: ""
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
end
