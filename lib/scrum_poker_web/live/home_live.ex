defmodule ScrumPokerWeb.HomeLive do
  use ScrumPokerWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center space-y-6 py-8">
        <div class="text-6xl">🃏</div>
        <h1 class="text-4xl font-bold tracking-tight">ScrumPoker</h1>
        <p class="text-lg text-base-content/70 max-w-md mx-auto">
          Real-time planning poker for agile teams. Vote on story points together, discuss
          differences, and reach consensus — all in one place.
        </p>

        <div class="flex flex-col sm:flex-row gap-4 justify-center items-center pt-4">
          <%= if @current_scope && @current_scope.user do %>
            <.link navigate={~p"/rooms/new"} class="btn btn-primary btn-lg">
              Create a Room
            </.link>
          <% else %>
            <.link navigate={~p"/users/log-in"} class="btn btn-primary btn-lg">
              Log in to Create a Room
            </.link>
          <% end %>

          <form phx-submit="join_room" class="flex gap-2">
            <input
              name="code"
              type="text"
              placeholder="Room code (e.g. A1B2C3)"
              class="input input-bordered uppercase"
              maxlength="6"
              autocomplete="off"
              phx-mounted={JS.focus()}
            />
            <button type="submit" class="btn btn-secondary">Join</button>
          </form>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mt-12 text-left">
          <div class="card bg-base-200">
            <div class="card-body">
              <h3 class="card-title text-base">1. Create a Room</h3>
              <p class="text-sm text-base-content/70">
                Scrum Master creates a session and shares the 6-character room code with the team.
              </p>
            </div>
          </div>
          <div class="card bg-base-200">
            <div class="card-body">
              <h3 class="card-title text-base">2. Vote Simultaneously</h3>
              <p class="text-sm text-base-content/70">
                Everyone picks a Fibonacci card in secret. Cards flip at the same moment.
              </p>
            </div>
          </div>
          <div class="card bg-base-200">
            <div class="card-body">
              <h3 class="card-title text-base">3. Reach Consensus</h3>
              <p class="text-sm text-base-content/70">
                Discuss outlier votes, re-vote if needed, and accept final story points.
              </p>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("join_room", %{"code" => code}, socket) do
    code = code |> String.trim() |> String.upcase()
    current_user = socket.assigns[:current_scope] && socket.assigns.current_scope.user

    if code == "" do
      {:noreply, put_flash(socket, :error, "Please enter a room code.")}
    else
      route = if current_user, do: ~p"/rooms/#{code}", else: ~p"/rooms/#{code}/join"
      {:noreply, push_navigate(socket, to: route)}
    end
  end
end
