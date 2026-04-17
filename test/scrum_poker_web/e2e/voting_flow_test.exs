defmodule ScrumPokerWeb.E2E.VotingFlowTest do
  @moduledoc """
  End-to-end tests for the core planning poker voting flow.

  These tests are written using the Persona DSL (Screenplay pattern) so
  they read like a business spec. Each test name describes a real-world
  scenario a stakeholder would care about.
  """

  use ScrumPokerWeb.ConnCase, async: true

  import ScrumPokerWeb.Persona

  describe "team estimation session" do
    test "team reaches consensus on a ticket" do
      # Setup: Alice creates a room, Bob joins as a guest
      alice = scrum_master("Alice")
      alice = creates_room(alice, "Sprint 42 Planning")

      bob = guest_voter("Bob")
      bob = joins_room(bob, alice.room_code, as: "Bob")

      # Alice queues a ticket and starts voting
      alice = adds_ticket(alice, external_id: "PROJ-123", title: "Add dark mode")
      alice = starts_next_ticket(alice)

      # Both vote the same value
      alice = votes(alice, "5")
      bob = votes(bob, "5")

      # Alice reveals — both should see consensus
      alice = reveals_cards(alice)
      alice |> sees_consensus_at("5")
      bob |> sees_consensus_at("5")

      # Alice accepts the points — both should see it in history
      alice = accepts_points(alice, "5")
      alice |> sees_in_history("PROJ-123", "5")
      bob |> sees_in_history("PROJ-123", "5")
    end

    test "team has split votes and discusses before re-voting" do
      alice = scrum_master("Alice")
      alice = creates_room(alice, "Sprint 42")

      bob = guest_voter("Bob") |> joins_room(alice.room_code)

      alice =
        alice
        |> adds_ticket(external_id: "PROJ-99", title: "Refactor auth")
        |> starts_next_ticket()

      # Disagreement
      alice = votes(alice, "5")
      bob = votes(bob, "13")

      alice = reveals_cards(alice)
      alice |> sees_no_consensus()

      # Re-vote: this time they agree
      alice = triggers_revote(alice)
      alice = votes(alice, "8")
      bob = votes(bob, "8")

      alice = reveals_cards(alice)
      alice |> sees_consensus_at("8")
    end

    test "scrum master ends the session and sees the summary" do
      alice = scrum_master("Alice")

      alice =
        alice
        |> creates_room("Sprint 42")
        |> adds_ticket(external_id: "PROJ-1", title: "Task one")
        |> starts_next_ticket()
        |> votes("3")
        |> reveals_cards()
        |> accepts_points("3")

      alice = ends_session(alice)
      alice |> sees_session_complete()
    end
  end

  describe "vote count visibility" do
    test "late joiner sees the correct vote count" do
      alice = scrum_master("Alice")

      alice =
        alice
        |> creates_room("Sprint 42")
        |> adds_ticket(external_id: "PROJ-1", title: "Task")
        |> starts_next_ticket()
        |> votes("5")

      # Bob arrives AFTER Alice has voted
      bob = guest_voter("Bob") |> joins_room(alice.room_code)

      # Bob should see "1 of 2 voted" right away (not 0 of 2)
      bob |> sees_vote_count(1, of: 2)

      bob = votes(bob, "5")
      # Now both see 2 of 2 — but only briefly before Alice reveals
      alice |> sees_vote_count(2, of: 2)
    end
  end
end
