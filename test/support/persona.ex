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
    :guest_token,
    :last_csv
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

  @doc "Builds an anonymous (logged-out) persona for testing auth flows."
  def anonymous(name) do
    %__MODULE__{
      name: name,
      type: :anonymous,
      conn: Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{})
    }
  end

  @doc "Gives the persona an existing (confirmed) account but doesn't log them in."
  def has_account_with_email(%__MODULE__{} = p, email) do
    user = ScrumPoker.AccountsFixtures.user_fixture(%{email: email})
    %{p | user: user}
  end

  @doc "Visits a path, mounting the LiveView at that route. Follows live redirects."
  def visits(%__MODULE__{} = p, path) do
    case live(p.conn, path) do
      {:ok, view, _html} ->
        %{p | view: view}

      {:error, {:live_redirect, %{to: to}}} ->
        visits(p, to)

      {:error, {:redirect, %{to: to}}} ->
        visits(p, to)
    end
  end

  @doc "Submits the registration form with the given email."
  def registers_with_email(%__MODULE__{} = p, email) do
    p.view
    |> form("#registration_form", user: %{email: email})
    |> render_submit()
    |> maybe_follow_redirect(p)
  end

  @doc "Types an email into the password login form (triggers phx-change)."
  def enters_in_password_form(%__MODULE__{} = p, email) do
    p.view
    |> form("#login_form_password", user: %{email: email, password: ""})
    |> render_change()

    p
  end

  @doc "Clicks the Forgot password? button on the login page."
  def clicks_forgot_password(%__MODULE__{} = p) do
    p.view
    |> element("button[phx-click='forgot_password']")
    |> render_click()
    |> maybe_follow_redirect(p)
  end

  @doc "Generates a fresh magic login token for the persona's account and visits the link."
  def opens_magic_link(%__MODULE__{user: user} = p) when not is_nil(user) do
    {token, _user_token} = ScrumPoker.AccountsFixtures.generate_user_magic_link_token(user)
    visits(p, "/users/log-in/#{token}")
  end

  defp maybe_follow_redirect(rendered_or_redirect, %__MODULE__{} = p) do
    case rendered_or_redirect do
      {:error, {:live_redirect, %{to: to}}} ->
        visits(p, to)

      {:error, {:redirect, %{to: to}}} ->
        visits(p, to)

      _html ->
        p
    end
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

  @doc "Asserts a room code is displayed in the persona's view."
  def sees_a_room_code(%__MODULE__{} = p) do
    html = render(p.view)
    assert p.room_code, "Persona has no room_code set"
    assert html =~ p.room_code, "Expected room code '#{p.room_code}' to be visible"
    p
  end

  @doc "Asserts a participant name appears in the participant list."
  def sees_in_participants(%__MODULE__{} = p, name) do
    html = render(p.view)
    assert html =~ name, "Expected '#{name}' to appear in participants"
    p
  end

  @doc "Asserts a specific number of pending tickets are in the queue."
  def sees_tickets_in_queue(%__MODULE__{} = p, count) do
    html = render(p.view)
    actual = Regex.scan(~r/phx-click="start_ticket"/, html) |> length()

    assert actual == count,
           "Expected #{count} ticket(s) in queue, found #{actual}"

    p
  end

  @doc "Asserts arbitrary text is visible to the persona."
  def sees_text(%__MODULE__{} = p, text) do
    html = render(p.view)
    assert html =~ text, "Expected to see '#{text}' on the page"
    p
  end

  @doc "Asserts a card with the given value is available for voting."
  def sees_card(%__MODULE__{} = p, value) do
    html = render(p.view)
    pattern = ~r/phx-value-card="#{Regex.escape(value)}"/

    assert Regex.match?(pattern, html),
           "Expected card '#{value}' to be available for voting"

    p
  end

  @doc "Downloads the session history CSV via the export endpoint."
  def downloads_history_csv(%__MODULE__{} = p) do
    conn = Phoenix.ConnTest.get(p.conn, "/rooms/#{p.room_code}/export.csv")
    %{p | last_csv: conn.resp_body}
  end

  @doc "Asserts the most recently downloaded CSV contains the given text."
  def csv_includes(%__MODULE__{last_csv: csv} = p, text) when is_binary(csv) do
    assert csv =~ text, "Expected CSV to contain '#{text}'"
    p
  end

  @doc "Re-mounts the persona's view to refresh state (useful after another persona triggers presence changes)."
  def refreshes(%__MODULE__{room_code: code} = p) when is_binary(code) do
    enter_room(p, code)
  end

  @doc """
  Imports a CSV string as if uploaded through the Jira import UI.
  Opens the form, uploads the file, and submits.
  """
  def imports_csv(%__MODULE__{} = p, csv_content) do
    p.view |> element("button[phx-click='toggle_import']") |> render_click()

    file = %{
      name: "tickets.csv",
      content: csv_content,
      type: "text/csv",
      last_modified: 1_700_000_000_000
    }

    input = file_input(p.view, "#import-form", :jira_csv, [file])
    render_upload(input, "tickets.csv")

    p.view |> form("#import-form") |> render_submit()
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
