defmodule ScrumPokerWeb.RoomLive.Join do
  use ScrumPokerWeb, :live_view

  alias ScrumPoker.Rooms

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-sm mx-auto text-center space-y-6">
        <div class="text-5xl">🃏</div>
        <.header>
          Join Room
          <:subtitle>
            You're joining <strong>{@room.name}</strong>
          </:subtitle>
        </.header>

        <.form for={@form} action={~p"/rooms/#{@room.code}/join"} method="post" class="space-y-4">
          <.input
            field={@form[:name]}
            label="Your Display Name"
            placeholder="e.g. Alice"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full">
            Join as Guest
          </.button>
        </.form>

        <div class="divider text-xs text-base-content/50">Have an account?</div>

        <.link navigate={~p"/users/log-in"} class="btn btn-outline w-full">
          Log in to join
        </.link>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    case Rooms.get_room_by_code(code) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Room not found.")
         |> push_navigate(to: ~p"/")}

      room ->
        form = to_form(%{"name" => ""}, as: "participant")
        {:ok, assign(socket, room: room, form: form)}
    end
  end
end
