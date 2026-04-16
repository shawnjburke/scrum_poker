defmodule ScrumPokerWeb.RoomLive.Show do
  use ScrumPokerWeb, :live_view

  alias ScrumPoker.{Rooms, RoomPresence}
  alias Phoenix.PubSub

  @impl true
  def mount(%{"code" => code}, session, socket) do
    case Rooms.get_room_by_code(code) do
      nil ->
        {:ok, socket |> put_flash(:error, "Room not found.") |> push_navigate(to: ~p"/")}

      room ->
        current_user = socket.assigns[:current_scope] && socket.assigns.current_scope.user
        guest_token = session["guest_token"]
        guest_name = session["guest_name"]

        cond do
          is_nil(current_user) && is_nil(guest_token) ->
            {:ok, redirect(socket, to: ~p"/rooms/#{code}/join")}

          true ->
            is_sm = !!(current_user && current_user.id == room.scrum_master_id)

            participant_name =
              cond do
                current_user -> current_user.display_name || current_user.email
                guest_name -> guest_name
                true -> "Guest"
              end

            presence_key =
              if current_user, do: "user:#{current_user.id}", else: "guest:#{guest_token}"

            if connected?(socket) do
              PubSub.subscribe(ScrumPoker.PubSub, "room:#{room.code}")

              RoomPresence.track(self(), "room:#{room.code}", presence_key, %{
                name: participant_name,
                role: (is_sm && "scrum_master") || "voter",
                voted: false
              })

              if current_user do
                Rooms.join_room(room,
                  user: current_user,
                  role: (is_sm && "scrum_master") || "voter"
                )
              end
            end

            room = Rooms.get_room_with_details!(code)
            presences = format_presences(RoomPresence.list("room:#{room.code}"))
            current_ticket = find_current_ticket(room)
            pending_tickets = find_pending_tickets(room)

            {:ok,
             socket
             |> assign(:room, room)
             |> assign(:current_ticket, current_ticket)
             |> assign(:votes, [])
             |> assign(:votes_revealed, current_ticket && current_ticket.status == "revealed")
             |> assign(:presences, presences)
             |> assign(:chat_messages, [])
             |> assign(:history, Rooms.list_accepted_tickets(room.id))
             |> assign(:my_vote, nil)
             |> assign(:is_scrum_master, is_sm)
             |> assign(:current_user, current_user)
             |> assign(:guest_token, guest_token)
             |> assign(:participant_name, participant_name)
             |> assign(:presence_key, presence_key)
             |> assign(:show_add_ticket_form, false)
             |> assign(:new_ticket_form, to_form(%{}, as: "ticket"))
             |> assign(:pending_tickets, pending_tickets)
             |> assign(:final_points_input, "")
             |> assign(:voted_keys, MapSet.new())
             |> assign(:vote_count, 0)
             |> assign(:voter_count, count_voters(presences))}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub & Presence handlers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    presences = format_presences(RoomPresence.list("room:#{socket.assigns.room.code}"))
    {:noreply, assign(socket, presences: presences, voter_count: count_voters(presences))}
  end

  def handle_info({:ticket_started, ticket}, socket) do
    {:noreply,
     socket
     |> assign(:current_ticket, ticket)
     |> assign(:votes, [])
     |> assign(:votes_revealed, false)
     |> assign(:my_vote, nil)
     |> assign(:voted_keys, MapSet.new())
     |> assign(:vote_count, 0)
     |> assign(:pending_tickets, Enum.reject(socket.assigns.pending_tickets, &(&1.id == ticket.id)))}
  end

  def handle_info({:votes_revealed, votes, ticket}, socket) do
    {:noreply,
     socket
     |> assign(:current_ticket, ticket)
     |> assign(:votes, votes)
     |> assign(:votes_revealed, true)}
  end

  def handle_info({:ticket_accepted, ticket}, socket) do
    {:noreply,
     socket
     |> assign(:current_ticket, nil)
     |> assign(:votes, [])
     |> assign(:votes_revealed, false)
     |> assign(:my_vote, nil)
     |> assign(:voted_keys, MapSet.new())
     |> assign(:vote_count, 0)
     |> assign(:history, socket.assigns.history ++ [ticket])}
  end

  def handle_info({:revote_triggered, ticket}, socket) do
    RoomPresence.update(self(), "room:#{socket.assigns.room.code}", socket.assigns.presence_key,
      &Map.put(&1, :voted, false))

    {:noreply,
     socket
     |> assign(:current_ticket, ticket)
     |> assign(:votes, [])
     |> assign(:votes_revealed, false)
     |> assign(:my_vote, nil)
     |> assign(:voted_keys, MapSet.new())
     |> assign(:vote_count, 0)}
  end

  def handle_info({:vote_cast, voter_key}, socket) do
    voted_keys = MapSet.put(socket.assigns.voted_keys, voter_key)
    {:noreply, assign(socket, voted_keys: voted_keys, vote_count: MapSet.size(voted_keys))}
  end

  def handle_info({:chat_message, msg}, socket) do
    messages = (socket.assigns.chat_messages ++ [msg]) |> Enum.take(-50)
    {:noreply, assign(socket, :chat_messages, messages)}
  end

  def handle_info({:ticket_added, ticket}, socket) do
    {:noreply, assign(socket, :pending_tickets, socket.assigns.pending_tickets ++ [ticket])}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("vote", %{"card" => value}, socket) do
    %{current_ticket: ticket, current_user: user, guest_token: guest_token,
      participant_name: name, presence_key: pkey, room: room} = socket.assigns

    if ticket && ticket.status == "voting" do
      Rooms.cast_vote(ticket, value,
        user_id: user && user.id,
        guest_token: guest_token,
        guest_name: name
      )

      RoomPresence.update(self(), "room:#{room.code}", pkey, &Map.put(&1, :voted, true))
      PubSub.broadcast(ScrumPoker.PubSub, "room:#{room.code}", {:vote_cast, pkey})

      {:noreply, assign(socket, :my_vote, value)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("reveal", _params, %{assigns: %{is_scrum_master: true}} = socket) do
    ticket = socket.assigns.current_ticket
    {:ok, updated_ticket} = Rooms.update_ticket_status(ticket, "revealed")
    raw_votes = Rooms.get_votes_for_ticket(ticket.id)
    votes = enrich_votes(raw_votes, socket.assigns.presences)

    PubSub.broadcast(ScrumPoker.PubSub, "room:#{socket.assigns.room.code}",
      {:votes_revealed, votes, updated_ticket})

    {:noreply, socket}
  end

  def handle_event("reveal", _params, socket), do: {:noreply, socket}

  def handle_event("accept", %{"points" => points}, %{assigns: %{is_scrum_master: true}} = socket)
      when points != "" do
    ticket = socket.assigns.current_ticket
    {:ok, accepted} = Rooms.accept_ticket(ticket, points)

    PubSub.broadcast(ScrumPoker.PubSub, "room:#{socket.assigns.room.code}",
      {:ticket_accepted, accepted})

    {:noreply, socket}
  end

  def handle_event("accept", _params, socket), do: {:noreply, socket}

  def handle_event("revote", _params, %{assigns: %{is_scrum_master: true}} = socket) do
    {:ok, updated} = Rooms.update_ticket_status(socket.assigns.current_ticket, "voting")
    PubSub.broadcast(ScrumPoker.PubSub, "room:#{socket.assigns.room.code}", {:revote_triggered, updated})
    {:noreply, socket}
  end

  def handle_event("revote", _params, socket), do: {:noreply, socket}

  def handle_event("start_ticket", %{"id" => id}, %{assigns: %{is_scrum_master: true}} = socket) do
    ticket = Rooms.get_ticket!(String.to_integer(id))
    {:ok, started} = Rooms.update_ticket_status(ticket, "voting")

    PubSub.broadcast(ScrumPoker.PubSub, "room:#{socket.assigns.room.code}",
      {:ticket_started, started})

    {:noreply, socket}
  end

  def handle_event("start_ticket", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_add_ticket", _params, socket) do
    {:noreply, assign(socket, :show_add_ticket_form, !socket.assigns.show_add_ticket_form)}
  end

  def handle_event("add_ticket", %{"ticket" => params}, %{assigns: %{is_scrum_master: true}} = socket) do
    case Rooms.add_ticket(socket.assigns.room, params) do
      {:ok, ticket} ->
        PubSub.broadcast(ScrumPoker.PubSub, "room:#{socket.assigns.room.code}",
          {:ticket_added, ticket})

        {:noreply,
         socket
         |> assign(:show_add_ticket_form, false)
         |> assign(:new_ticket_form, to_form(%{}, as: "ticket"))}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_ticket_form, to_form(changeset, as: "ticket"))}
    end
  end

  def handle_event("add_ticket", _params, socket), do: {:noreply, socket}

  def handle_event("send_chat", %{"message" => text}, socket) when text != "" do
    msg = %{id: System.unique_integer([:positive]), name: socket.assigns.participant_name, text: text}
    PubSub.broadcast(ScrumPoker.PubSub, "room:#{socket.assigns.room.code}", {:chat_message, msg})
    {:noreply, socket}
  end

  def handle_event("send_chat", _params, socket), do: {:noreply, socket}

  def handle_event("update_final_points", %{"final_points" => v}, socket) do
    {:noreply, assign(socket, :final_points_input, v)}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-base-100">
      <%!-- Room header --%>
      <div class="navbar bg-base-200 shadow-sm px-4 gap-3 flex-shrink-0">
        <div class="flex-1 min-w-0">
          <span class="font-bold text-base truncate">{@room.name}</span>
          <span class="badge badge-neutral font-mono text-xs ml-2">{@room.code}</span>
        </div>
        <div class="flex items-center gap-2 flex-shrink-0">
          <span class="text-sm hidden md:block text-base-content/70">
            {@participant_name}
            <span :if={is_nil(@current_user)} class="badge badge-ghost badge-xs ml-1">guest</span>
          </span>
          <Layouts.theme_toggle />
          <.link :if={@current_user} href={~p"/users/log-out"} method="delete" class="btn btn-sm btn-ghost">
            Log out
          </.link>
        </div>
      </div>

      <%!-- Main 3-column layout --%>
      <div class="flex-1 grid grid-cols-1 lg:grid-cols-[200px_1fr_200px] overflow-hidden min-h-0">

        <%!-- Left: Participants --%>
        <aside class="bg-base-200/40 border-r border-base-300 p-4 overflow-y-auto hidden lg:flex lg:flex-col gap-3">
          <h3 class="font-semibold text-xs uppercase tracking-wider text-base-content/50">
            Participants ({length(@presences)})
          </h3>
          <ul class="space-y-2">
            <li :for={p <- @presences} class="flex items-center gap-2 text-sm min-w-0">
              <span class={[
                "size-2.5 rounded-full flex-shrink-0",
                p.meta.voted && "bg-success",
                !p.meta.voted && "bg-base-300"
              ]}>
              </span>
              <span class="truncate flex-1">{p.meta.name}</span>
              <span :if={p.meta.role == "scrum_master"} class="badge badge-primary badge-xs">SM</span>
              <span :if={@votes_revealed && p.meta.voted} class="badge badge-neutral badge-sm font-mono">
                {participant_vote_value(p, @votes)}
              </span>
            </li>
          </ul>
          <p :if={Enum.empty?(@presences)} class="text-xs text-base-content/40 italic">No one here yet</p>

          <div class="text-xs text-base-content/40 mt-auto pt-2 border-t border-base-300">
            <div>Code: <span class="font-mono font-bold">{@room.code}</span></div>
          </div>
        </aside>

        <%!-- Center: Voting area --%>
        <main class="flex flex-col overflow-y-auto p-4 sm:p-6 gap-6">
          <%= cond do %>
            <% is_nil(@current_ticket) -> %>
              <%!-- Waiting state --%>
              <div class="flex flex-col items-center justify-center flex-1 text-center gap-4 py-12">
                <div class="text-5xl">⏳</div>
                <h2 class="text-xl font-semibold">Waiting to start</h2>
                <%= if @is_scrum_master do %>
                  <p class="text-base-content/60 text-sm">
                    Add a ticket to the queue and click <strong>Start</strong> to begin voting.
                  </p>
                <% else %>
                  <p class="text-base-content/60 text-sm">
                    Waiting for the Scrum Master to start a ticket...
                  </p>
                <% end %>
              </div>

            <% @current_ticket.status in ["voting", "revealed"] -> %>
              <div class="space-y-5 max-w-2xl mx-auto w-full">
                <%!-- Ticket card --%>
                <div class="card bg-base-200">
                  <div class="card-body py-4">
                    <div class="flex items-start gap-3">
                      <div class="flex-1 min-w-0">
                        <div :if={@current_ticket.external_id} class="badge badge-outline badge-sm font-mono mb-1">
                          {@current_ticket.external_id}
                        </div>
                        <h2 class="font-bold text-lg leading-tight">{@current_ticket.title}</h2>
                        <p :if={@current_ticket.description} class="text-sm text-base-content/70 mt-1">
                          {@current_ticket.description}
                        </p>
                      </div>
                      <a :if={@current_ticket.url} href={@current_ticket.url} target="_blank"
                         class="btn btn-sm btn-ghost flex-shrink-0">
                        <.icon name="hero-arrow-top-right-on-square" class="size-4" />
                      </a>
                    </div>
                  </div>
                </div>

                <%!-- Voting (before reveal) --%>
                <div :if={@current_ticket.status == "voting" && !@votes_revealed} class="space-y-5">
                  <div class="text-center">
                    <p class="text-sm text-base-content/60 mb-2">
                      {@vote_count} of {@voter_count} voted
                    </p>
                    <progress class="progress progress-primary w-48" value={@vote_count} max={max(@voter_count, 1)}>
                    </progress>
                  </div>

                  <div>
                    <p class="text-xs text-center text-base-content/40 mb-3 uppercase tracking-wider">
                      Pick your estimate
                    </p>
                    <div class="flex flex-wrap gap-2 justify-center">
                      <button
                        :for={value <- card_values(@room)}
                        phx-click="vote"
                        phx-value-card={value}
                        class={[
                          "btn w-14 h-20 text-lg font-bold border-2 transition-all duration-150",
                          @my_vote == value && "btn-primary border-primary scale-110 shadow-lg",
                          @my_vote != value && "btn-outline hover:scale-105"
                        ]}
                      >
                        {value}
                      </button>
                    </div>
                  </div>

                  <div :if={@is_scrum_master} class="flex justify-center">
                    <button phx-click="reveal" class="btn btn-primary">
                      <.icon name="hero-eye" class="size-4" /> Reveal Cards
                    </button>
                  </div>
                </div>

                <%!-- Results (after reveal) --%>
                <div :if={@votes_revealed} class="space-y-5">
                  <h3 class="font-semibold text-center text-sm uppercase tracking-wider text-base-content/60">
                    Results
                  </h3>

                  <%!-- Vote distribution --%>
                  <div class="flex flex-wrap gap-4 justify-center">
                    <div :for={{value, voters} <- vote_distribution(@votes)} class="flex flex-col items-center gap-1">
                      <div class="card bg-primary text-primary-content w-14 h-20 flex items-center justify-center text-xl font-bold shadow-md">
                        {value}
                      </div>
                      <span :for={name <- voters} class="text-xs text-center">{name}</span>
                    </div>
                  </div>

                  <%!-- Consensus / spread --%>
                  <div class={["alert justify-center text-center text-sm",
                               consensus?(@votes) && "alert-success" || "alert-warning"]}>
                    <%= if consensus?(@votes) do %>
                      🎉 Consensus! Everyone voted <strong class="mx-1">{hd(@votes).value}</strong>
                    <% else %>
                      Votes differ — discuss before accepting.
                    <% end %>
                  </div>

                  <%!-- SM accept controls --%>
                  <div :if={@is_scrum_master} class="card bg-base-200">
                    <div class="card-body py-4 gap-3">
                      <h4 class="font-semibold text-sm">Accept story points</h4>
                      <div class="flex flex-wrap gap-2">
                        <button
                          :for={value <- suggested_values(@votes)}
                          phx-click="accept"
                          phx-value-points={value}
                          class="btn btn-primary btn-sm font-mono"
                        >
                          {value}
                        </button>
                      </div>
                      <div class="flex gap-2">
                        <input
                          type="text"
                          name="final_points"
                          placeholder="Custom..."
                          value={@final_points_input}
                          phx-change="update_final_points"
                          class="input input-bordered input-sm flex-1"
                        />
                        <button
                          phx-click="accept"
                          phx-value-points={@final_points_input}
                          class="btn btn-primary btn-sm"
                          disabled={@final_points_input == ""}
                        >
                          Accept
                        </button>
                      </div>
                      <button phx-click="revote" class="btn btn-ghost btn-sm">
                        <.icon name="hero-arrow-path" class="size-4" /> Re-vote
                      </button>
                    </div>
                  </div>
                </div>
              </div>

            <% true -> %>
              <div class="flex flex-col items-center justify-center flex-1 text-center gap-2 py-12">
                <div class="text-4xl">✅</div>
                <p class="text-base-content/60 text-sm">Ticket accepted. Pick the next one.</p>
              </div>
          <% end %>

          <%!-- SM: Add ticket + queue --%>
          <div :if={@is_scrum_master} class="max-w-2xl mx-auto w-full border-t border-base-300 pt-4 space-y-3">
            <button phx-click="toggle_add_ticket" class="btn btn-sm btn-outline">
              <.icon name={if @show_add_ticket_form, do: "hero-minus", else: "hero-plus"} class="size-4" />
              {if @show_add_ticket_form, do: "Cancel", else: "Add Ticket"}
            </button>

            <div :if={@show_add_ticket_form} class="card bg-base-200">
              <div class="card-body py-4">
                <.form for={@new_ticket_form} phx-submit="add_ticket" class="space-y-2">
                  <div class="flex gap-2">
                    <.input
                      field={@new_ticket_form[:external_id]}
                      placeholder="PROJ-123"
                      class="input input-bordered input-sm w-28"
                      label=""
                    />
                    <.input
                      field={@new_ticket_form[:title]}
                      placeholder="Ticket title (required)"
                      class="input input-bordered input-sm flex-1"
                      label=""
                    />
                  </div>
                  <.input
                    field={@new_ticket_form[:url]}
                    placeholder="https://... (optional)"
                    class="input input-bordered input-sm w-full"
                    label=""
                  />
                  <.button class="btn btn-primary btn-sm">Add to Queue</.button>
                </.form>
              </div>
            </div>

            <div :if={!Enum.empty?(@pending_tickets)} class="space-y-1">
              <h4 class="text-xs uppercase tracking-wider text-base-content/50">Queue</h4>
              <div :for={t <- @pending_tickets} class="flex items-center gap-2 p-2 rounded-lg bg-base-200/60 text-sm">
                <span :if={t.external_id} class="badge badge-outline badge-xs font-mono">{t.external_id}</span>
                <span class="flex-1 truncate">{t.title}</span>
                <button
                  :if={is_nil(@current_ticket) || @current_ticket.status == "accepted"}
                  phx-click="start_ticket"
                  phx-value-id={t.id}
                  class="btn btn-xs btn-primary"
                >
                  Start
                </button>
              </div>
            </div>
          </div>
        </main>

        <%!-- Right: History --%>
        <aside class="bg-base-200/40 border-l border-base-300 p-4 overflow-y-auto hidden lg:flex lg:flex-col gap-3">
          <h3 class="font-semibold text-xs uppercase tracking-wider text-base-content/50">
            Session History
          </h3>
          <p :if={Enum.empty?(@history)} class="text-xs text-base-content/40 italic">
            No accepted tickets yet
          </p>
          <ul class="space-y-2">
            <li :for={t <- @history} class="flex items-start gap-1 text-xs">
              <div class="flex-1 min-w-0">
                <span :if={t.external_id} class="font-mono text-base-content/60">{t.external_id} </span>
                <span class="break-words">{t.title}</span>
              </div>
              <span class="badge badge-primary badge-sm font-mono flex-shrink-0">{t.final_points}</span>
            </li>
          </ul>
        </aside>
      </div>

      <%!-- Discussion / Chat --%>
      <div :if={@votes_revealed || !Enum.empty?(@chat_messages)}
           class="border-t border-base-300 bg-base-100 flex-shrink-0">
        <div class="max-w-2xl mx-auto p-4 space-y-2">
          <h4 class="text-xs uppercase tracking-wider text-base-content/50">Discussion</h4>
          <div class="space-y-1 max-h-28 overflow-y-auto text-sm">
            <div :for={msg <- @chat_messages} class="leading-snug">
              <span class="font-semibold">{msg.name}:</span>
              <span class="text-base-content/80 ml-1">{msg.text}</span>
            </div>
          </div>
          <form phx-submit="send_chat" class="flex gap-2 mt-1">
            <input
              type="text"
              name="message"
              placeholder="Add to discussion..."
              class="input input-bordered input-sm flex-1"
              autocomplete="off"
              phx-hook="ClearOnSubmit"
              id="chat-input"
            />
            <button type="submit" class="btn btn-primary btn-sm">Send</button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp format_presences(presences) do
    presences
    |> Enum.map(fn {key, %{metas: [meta | _]}} -> %{key: key, meta: meta} end)
    |> Enum.sort_by(& &1.meta.name)
  end

  defp count_voters(presences), do: Enum.count(presences, &(&1.meta.role != "observer"))

  defp find_current_ticket(%{tickets: tickets}),
    do: Enum.find(tickets, &(&1.status in ["voting", "revealed"]))
  defp find_current_ticket(_), do: nil

  defp find_pending_tickets(%{tickets: tickets}),
    do: Enum.filter(tickets, &(&1.status == "pending"))
  defp find_pending_tickets(_), do: []

  defp card_values(room), do: ScrumPoker.Rooms.Room.card_values(room.card_deck)

  defp vote_distribution(votes) do
    votes
    |> Enum.group_by(& &1.value, & &1.voter_name)
    |> Enum.sort_by(fn {v, _} -> sort_value(v) end)
  end

  defp consensus?([_ | _] = votes) do
    real = votes |> Enum.map(& &1.value) |> Enum.reject(&(&1 in ["?", "☕"]))
    length(real) > 0 && length(Enum.uniq(real)) == 1
  end
  defp consensus?(_), do: false

  defp suggested_values(votes) do
    votes |> Enum.map(& &1.value) |> Enum.uniq() |> Enum.sort_by(&sort_value/1)
  end

  defp sort_value("?"), do: 999
  defp sort_value("☕"), do: 1000

  defp sort_value(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> 500
    end
  end

  defp participant_vote_value(p, votes) do
    Enum.find_value(votes, "—", fn v ->
      if Map.get(v, :voter_key) == p.key, do: v.value
    end)
  end

  defp enrich_votes(votes, presences) do
    Enum.map(votes, fn vote ->
      voter_key = if vote.user_id, do: "user:#{vote.user_id}", else: "guest:#{vote.guest_token}"
      voter_name =
        case Enum.find(presences, &(&1.key == voter_key)) do
          nil -> vote.guest_name || "Unknown"
          p -> p.meta.name
        end

      vote
      |> Map.put(:voter_name, voter_name)
      |> Map.put(:voter_key, voter_key)
    end)
  end
end
