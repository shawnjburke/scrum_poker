defmodule ScrumPokerWeb.Features.RoomManagementTest do
  @moduledoc """
  Step definitions for `room_management.feature`.
  """
  use Cabbage.Feature, async: false, file: "room_management.feature"

  import ScrumPokerWeb.Persona

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ScrumPoker.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  # Givens

  defgiven ~r/^Alice is logged in as a Scrum Master$/, _, state do
    {:ok, Map.put(state, :alice, scrum_master("Alice"))}
  end

  defgiven ~r/^Alice has created a room "(?<name>[^"]+)"$/, %{name: name}, state do
    alice = scrum_master("Alice") |> creates_room(name)
    {:ok, Map.put(state, :alice, alice)}
  end

  # Whens

  defwhen ~r/^Alice creates a room "(?<name>[^"]+)" using the "(?<deck>[^"]+)" deck$/,
          %{name: name, deck: deck}, state do
    alice = creates_room(state.alice, name, deck: deck)
    {:ok, Map.put(state, :alice, alice)}
  end

  defwhen ~r/^Bob joins the room as a guest named "(?<name>[^"]+)"$/, %{name: name}, state do
    bob = guest_voter(name) |> joins_room(state.alice.room_code)
    # Re-render Alice to pick up the new participant via presence
    alice = refreshes(state.alice)
    {:ok, state |> Map.put(:bob, bob) |> Map.put(:alice, alice)}
  end

  defwhen ~r/^Alice adds a ticket "(?<id>[^"]+)" titled "(?<title>[^"]+)"$/,
          %{id: id, title: title}, state do
    alice = adds_ticket(state.alice, external_id: id, title: title)
    {:ok, Map.put(state, :alice, alice)}
  end

  defwhen ~r/^Alice starts voting on the next ticket$/, _, state do
    {:ok, Map.put(state, :alice, starts_next_ticket(state.alice))}
  end

  defwhen ~r/^Alice votes "(?<v>[^"]+)"$/, %{v: v}, state do
    {:ok, Map.put(state, :alice, votes(state.alice, v))}
  end

  defwhen ~r/^Alice reveals the cards$/, _, state do
    {:ok, Map.put(state, :alice, reveals_cards(state.alice))}
  end

  defwhen ~r/^Alice accepts "(?<p>[^"]+)" story points$/, %{p: p}, state do
    {:ok, Map.put(state, :alice, accepts_points(state.alice, p))}
  end

  defwhen ~r/^Alice ends the session$/, _, state do
    {:ok, Map.put(state, :alice, ends_session(state.alice))}
  end

  # Thens

  defthen ~r/^Alice sees the room "(?<name>[^"]+)"$/, %{name: name}, state do
    is_in_room(state.alice, name)
    :ok
  end

  defthen ~r/^Bob sees the room "(?<name>[^"]+)"$/, %{name: name}, state do
    is_in_room(state.bob, name)
    :ok
  end

  defthen ~r/^Alice sees a unique room code$/, _, state do
    sees_a_room_code(state.alice)
    :ok
  end

  defthen ~r/^Alice sees "(?<name>[^"]+)" in the participant list$/, %{name: name}, state do
    sees_in_participants(state.alice, name)
    :ok
  end

  defthen ~r/^Alice sees "(?<text>[^"]+)"$/, %{text: text}, state do
    sees_text(state.alice, text)
    :ok
  end
end
