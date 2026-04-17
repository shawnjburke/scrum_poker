defmodule ScrumPokerWeb.RoomLive.Index do
  use ScrumPokerWeb, :live_view

  alias ScrumPoker.Rooms

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <.header>
            My Rooms
            <:subtitle>Sessions you've created as Scrum Master</:subtitle>
          </.header>
          <.link navigate={~p"/rooms/new"} class="btn btn-primary btn-sm">
            <.icon name="hero-plus" class="size-4" /> New Room
          </.link>
        </div>

        <%= if Enum.empty?(@rooms) do %>
          <div class="text-center py-12 space-y-3">
            <div class="text-4xl">🃏</div>
            <p class="text-base-content/60">You haven't created any rooms yet.</p>
            <.link navigate={~p"/rooms/new"} class="btn btn-primary">Create your first room</.link>
          </div>
        <% else %>
          <div class="space-y-2">
            <div :for={room <- @rooms}
                 class="card bg-base-200 hover:bg-base-300 transition-colors cursor-pointer">
              <.link navigate={~p"/rooms/#{room.code}"} class="card-body py-4 flex-row items-center gap-4">
                <div class="flex-1 min-w-0">
                  <h3 class="font-semibold">{room.name}</h3>
                  <div class="flex items-center gap-3 text-sm text-base-content/60 mt-1">
                    <span class="badge badge-neutral badge-sm font-mono">{room.code}</span>
                    <span>{format_deck(room.card_deck)}</span>
                    <span>{format_date(room.inserted_at)}</span>
                  </div>
                </div>
                <div>
                  <span class={["badge badge-sm",
                                room.status == "concluded" && "badge-ghost",
                                room.status != "concluded" && "badge-success"]}>
                    {room.status}
                  </span>
                </div>
              </.link>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    rooms = Rooms.list_rooms_for_user(user.id)
    {:ok, assign(socket, rooms: rooms)}
  end

  defp format_deck("fibonacci"), do: "Fibonacci"
  defp format_deck("modified_fibonacci"), do: "Modified Fibonacci"
  defp format_deck("tshirt"), do: "T-Shirt"
  defp format_deck("dogs"), do: "Dogs"
  defp format_deck(other), do: other

  defp format_date(dt), do: Calendar.strftime(dt, "%b %d, %Y")
end
