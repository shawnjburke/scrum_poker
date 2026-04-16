defmodule ScrumPokerWeb.RoomLive.New do
  use ScrumPokerWeb, :live_view

  alias ScrumPoker.Rooms

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-md mx-auto">
        <.header>
          Create a Room
          <:subtitle>You'll be the Scrum Master for this session.</:subtitle>
        </.header>

        <.form for={@form} phx-submit="create" class="space-y-4 mt-6">
          <.input
            field={@form[:name]}
            label="Session Name"
            placeholder="e.g. Sprint 42 Planning"
            required
            phx-mounted={JS.focus()}
          />

          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Card Deck</span>
            </label>
            <select name="room[card_deck]" class="select select-bordered w-full">
              <option value="fibonacci" selected={@form[:card_deck].value == "fibonacci"}>
                Fibonacci (0, 1, 2, 3, 5, 8, 13, 21, 40, 100)
              </option>
              <option
                value="modified_fibonacci"
                selected={@form[:card_deck].value == "modified_fibonacci"}
              >
                Modified Fibonacci (0, ½, 1, 2, 3, 5, 8, 13, 20, 40, 100)
              </option>
              <option value="tshirt" selected={@form[:card_deck].value == "tshirt"}>
                T-Shirt Sizes (XS, S, M, L, XL, XXL)
              </option>
              <option value="dogs" selected={@form[:card_deck].value == "dogs"}>
                Dogs — Relative Sizing (Chihuahua to Saint Bernard)
              </option>
            </select>
          </div>

          <.button class="btn btn-primary w-full mt-2" phx-disable-with="Creating...">
            Create Room
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{"name" => "", "card_deck" => "fibonacci"}, as: "room")
    {:ok, assign(socket, form: form)}
  end

  @impl true
  def handle_event("create", %{"room" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Rooms.create_room(params, user) do
      {:ok, room} ->
        {:noreply, push_navigate(socket, to: ~p"/rooms/#{room.code}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "room"))}
    end
  end
end
