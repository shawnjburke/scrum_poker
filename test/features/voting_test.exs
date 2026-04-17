defmodule ScrumPokerWeb.Features.VotingTest do
  @moduledoc """
  Cucumber/Gherkin step definitions for `voting.feature`.

  Each step delegates to the Persona DSL so the business spec
  (the .feature file) and the engineering DSL stay in sync.
  Read the .feature file alongside this file — it is the spec
  this test enforces.
  """
  use Cabbage.Feature, async: false, file: "voting.feature"

  import ScrumPokerWeb.Persona

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ScrumPoker.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  # Givens

  defgiven ~r/^Alice has created a room "(?<name>[^"]+)"$/, %{name: name}, state do
    alice = scrum_master("Alice") |> creates_room(name)
    {:ok, Map.put(state, :alice, alice)}
  end

  defgiven ~r/^Bob has joined the room as a guest$/, _, state do
    bob = guest_voter("Bob") |> joins_room(state.alice.room_code)
    {:ok, Map.put(state, :bob, bob)}
  end

  # Whens

  defwhen ~r/^Alice adds a ticket "(?<id>[^"]+)" titled "(?<title>[^"]+)"$/,
          %{id: id, title: title}, state do
    alice = adds_ticket(state.alice, external_id: id, title: title)
    {:ok, Map.put(state, :alice, alice)}
  end

  defwhen ~r/^Alice starts voting on the next ticket$/, _, state do
    alice = starts_next_ticket(state.alice)
    {:ok, Map.put(state, :alice, alice)}
  end

  defwhen ~r/^Alice votes "(?<value>[^"]+)"$/, %{value: value}, state do
    alice = votes(state.alice, value)
    {:ok, Map.put(state, :alice, alice)}
  end

  defwhen ~r/^Bob votes "(?<value>[^"]+)"$/, %{value: value}, state do
    bob = votes(state.bob, value)
    {:ok, Map.put(state, :bob, bob)}
  end

  defwhen ~r/^Alice reveals the cards$/, _, state do
    alice = reveals_cards(state.alice)
    {:ok, Map.put(state, :alice, alice)}
  end

  defwhen ~r/^Alice triggers a re-vote$/, _, state do
    alice = triggers_revote(state.alice)
    {:ok, Map.put(state, :alice, alice)}
  end

  defwhen ~r/^Alice accepts "(?<points>[^"]+)" story points$/, %{points: points}, state do
    alice = accepts_points(state.alice, points)
    {:ok, Map.put(state, :alice, alice)}
  end

  # Thens

  defthen ~r/^Alice sees consensus at "(?<value>[^"]+)"$/, %{value: value}, state do
    sees_consensus_at(state.alice, value)
    :ok
  end

  defthen ~r/^Bob sees consensus at "(?<value>[^"]+)"$/, %{value: value}, state do
    sees_consensus_at(state.bob, value)
    :ok
  end

  defthen ~r/^Alice sees no consensus$/, _, state do
    sees_no_consensus(state.alice)
    :ok
  end

  defthen ~r/^Alice sees "(?<id>[^"]+)" in the session history with "(?<points>[^"]+)" points$/,
          %{id: id, points: points}, state do
    sees_in_history(state.alice, id, points)
    :ok
  end

  defthen ~r/^Bob sees "(?<id>[^"]+)" in the session history with "(?<points>[^"]+)" points$/,
          %{id: id, points: points}, state do
    sees_in_history(state.bob, id, points)
    :ok
  end
end
