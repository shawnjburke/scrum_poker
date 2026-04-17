defmodule ScrumPokerWeb.Persona do
  @moduledoc """
  Screenplay-style test DSL for ScrumPoker.

  A Persona represents an actor in the system (Scrum Master, Voter, Guest)
  with their own LiveView session. Functions are chainable and read like
  business prose:

      alice = Persona.scrum_master("Alice")
      bob = Persona.guest_voter("Bob")

      alice |> creates_room("Sprint 42")
      bob |> joins_room(alice.room_code)
      alice |> adds_ticket(external_id: "PROJ-1", title: "Add dark mode")
      alice |> starts_next_ticket()
      [alice, bob] |> all_vote("5")
      alice |> reveals_cards()
      alice |> sees_consensus_at("5")
      alice |> accepts_points("5")

  The DSL is split into:
    * Constructors: `scrum_master/1`, `guest_voter/1`
    * Tasks (state-changing actions): `creates_room/2`, `votes/2`, `reveals_cards/1`, ...
    * Questions (assertions): `sees_consensus_at/2`, `sees_vote_count/3`, ...
  """

  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias ScrumPoker.{Accounts, Rooms}

  @endpoint ScrumPokerWeb.Endpoint

  defstruct [
    :name,
    :type,
    :conn,
    :view,
    :user,
    :room,
    :room_code,
    :guest_token
  ]

  # ---------------------------------------------------------------------------
  # Constructors
  # ---------------------------------------------------------------------------

  @doc "Builds an authenticated Scrum Master persona."
  def scrum_master(name) do
    {:ok, user} = Accounts.register_user(%{email: "#{slug(name)}@test.local"})
    user = confirm(user) |> set_display_name(name)

    %__MODULE__{
      name: name,
      type: :scrum_master,
      conn: build_authenticated_conn(user),
      user: user
    }
  end

  @doc "Builds a guest voter persona (no account)."
  def guest_voter(name) do
    %__MODULE__{
      name: name,
      type: :guest,
      conn: Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{})
    }
  end

  # ---------------------------------------------------------------------------
  # Tasks — state-changing actions
  # ---------------------------------------------------------------------------

  @doc "Creates a room as the scrum master and navigates into it."
  def creates_room(%__MODULE__{type: :scrum_master} = p, name, opts \\ []) do
    deck = Keyword.get(opts, :deck, "fibonacci")
    {:ok, room} = Rooms.create_room(%{"name" => name, "card_deck" => deck}, p.user)
    enter_room(p, room.code)
  end

  @doc "Joins an existing room. Guests provide a display name; SM auto-uses their account."
  def joins_room(persona, room_code, opts \\ [])

  def joins_room(%__MODULE__{type: :guest} = p, room_code, opts) do
    name = Keyword.get(opts, :as, p.name)
    room = Rooms.get_room_by_code!(room_code)
    guest_token = generate_token()

    {:ok, _participant} =
      Rooms.join_room(room, guest_name: name, guest_token: guest_token, role: "voter")

    conn =
      p.conn
      |> Plug.Test.init_test_session(%{guest_token: guest_token, guest_name: name})

    %{p | conn: conn, guest_token: guest_token, name: name}
    |> enter_room(room_code)
  end

  def joins_room(%__MODULE__{type: :scrum_master} = p, room_code, _opts) do
    enter_room(p, room_code)
  end

  @doc "Adds a ticket to the queue (SM only)."
  def adds_ticket(%__MODULE__{} = p, attrs) do
    params =
      attrs
      |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      |> Map.new()

    # Expand the add-ticket form if it's collapsed
    p.view |> element("button[phx-click='toggle_add_ticket']") |> render_click()

    p.view
    |> form("form[phx-submit='add_ticket']", ticket: params)
    |> render_submit()

    p
  end

  @doc "Starts voting on the first pending ticket in the queue."
  def starts_next_ticket(%__MODULE__{} = p) do
    [next | _] = pending_tickets(p)

    p.view
    |> element("button[phx-click='start_ticket'][phx-value-id='#{next.id}']")
    |> render_click()

    p
  end

  @doc "Casts a vote with the given card value."
  def votes(%__MODULE__{} = p, value) do
    p.view
    |> element("button[phx-click='vote'][phx-value-card='#{value}']")
    |> render_click()

    p
  end

  @doc "All listed personas vote the same value."
  def all_vote(personas, value) when is_list(personas) do
    Enum.map(personas, &votes(&1, value))
  end

  @doc "Reveals the cards (SM only)."
  def reveals_cards(%__MODULE__{} = p) do
    p.view |> element("button[phx-click='reveal']") |> render_click()
    p
  end

  @doc "Accepts the given story point value (SM only)."
  def accepts_points(%__MODULE__{} = p, points) do
    p.view
    |> element("button[phx-click='accept'][phx-value-points='#{points}']")
    |> render_click()

    p
  end

  @doc "Triggers a re-vote (SM only)."
  def triggers_revote(%__MODULE__{} = p) do
    p.view |> element("button[phx-click='revote']") |> render_click()
    p
  end

  @doc "Ends the session (SM only)."
  def ends_session(%__MODULE__{} = p) do
    p.view |> element("button[phx-click='end_session']") |> render_click()
    p
  end

  # ---------------------------------------------------------------------------
  # Questions — assertions about what the persona sees
  # ---------------------------------------------------------------------------

  @doc "Asserts the persona's view shows the consensus message with the given value."
  def sees_consensus_at(%__MODULE__{} = p, value) do
    html = render(p.view)
    assert html =~ "Consensus", "Expected #{p.name} to see Consensus, got:\n#{html}"
    assert html =~ value, "Expected #{p.name} to see consensus value #{value}"
    p
  end

  @doc "Asserts no consensus is shown — votes differ."
  def sees_no_consensus(%__MODULE__{} = p) do
    html = render(p.view)
    assert html =~ "Votes differ", "Expected #{p.name} to see 'Votes differ' message"
    p
  end

  @doc "Asserts the vote count display shows X of Y."
  def sees_vote_count(%__MODULE__{} = p, voted, of: total) do
    html = render(p.view)
    expected = "#{voted} of #{total} voted"

    assert html =~ expected,
           "Expected #{p.name} to see '#{expected}', got:\n#{html}"

    p
  end

  @doc "Asserts a ticket appears in the session history with the given final points."
  def sees_in_history(%__MODULE__{} = p, ticket_identifier, points) do
    html = render(p.view)

    assert html =~ ticket_identifier,
           "Expected #{p.name} to see ticket '#{ticket_identifier}' in history"

    assert html =~ points,
           "Expected #{p.name} to see points '#{points}' in history"

    p
  end

  @doc "Asserts the room is in concluded state showing the summary."
  def sees_session_complete(%__MODULE__{} = p) do
    html = render(p.view)
    assert html =~ "Session Complete", "Expected #{p.name} to see Session Complete"
    p
  end

  @doc "Asserts the persona is currently looking at the room (the room name is in the page)."
  def is_in_room(%__MODULE__{} = p, room_name) do
    html = render(p.view)
    assert html =~ room_name, "Expected #{p.name} to be in room '#{room_name}'"
    p
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp enter_room(%__MODULE__{} = p, room_code) do
    {:ok, view, _html} = live(p.conn, "/rooms/#{room_code}")
    room = Rooms.get_room_by_code!(room_code)
    %{p | view: view, room: room, room_code: room_code}
  end

  defp pending_tickets(%__MODULE__{room_code: code}) do
    code |> Rooms.get_room_with_details!() |> Map.get(:tickets) |> Enum.filter(&(&1.status == "pending"))
  end

  defp build_authenticated_conn(user) do
    token = Accounts.generate_user_session_token(user)

    Phoenix.ConnTest.build_conn()
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  defp confirm(user) do
    user
    |> ScrumPoker.Accounts.User.confirm_changeset()
    |> ScrumPoker.Repo.update!()
  end

  defp set_display_name(user, name) do
    {:ok, user} = Accounts.update_user_profile(user, %{"display_name" => name})
    user
  end

  defp slug(name) do
    base = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_")
    "#{base}_#{System.unique_integer([:positive])}"
  end

  defp generate_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
