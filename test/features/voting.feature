# Requirement: Teams need to estimate ticket complexity together without
# anchoring on the first vote. Cards stay hidden until the Scrum Master
# reveals them simultaneously.

Feature: Planning Poker Voting
  As a Scrum Master
  I want my team to vote on story complexity simultaneously
  So that no one anchors on the first estimate

  Scenario: Team reaches consensus on a ticket
    Given Alice has created a room "Sprint 42 Planning"
    And Bob has joined the room as a guest
    When Alice adds a ticket "PROJ-123" titled "Add dark mode"
    And Alice starts voting on the next ticket
    And Alice votes "5"
    And Bob votes "5"
    And Alice reveals the cards
    Then Alice sees consensus at "5"
    And Bob sees consensus at "5"

  Scenario: Team disagrees and re-votes to consensus
    Given Alice has created a room "Sprint 42 Planning"
    And Bob has joined the room as a guest
    When Alice adds a ticket "PROJ-99" titled "Refactor auth"
    And Alice starts voting on the next ticket
    And Alice votes "5"
    And Bob votes "13"
    And Alice reveals the cards
    Then Alice sees no consensus
    When Alice triggers a re-vote
    And Alice votes "8"
    And Bob votes "8"
    And Alice reveals the cards
    Then Alice sees consensus at "8"

  Scenario: Scrum master accepts story points and ticket appears in history
    Given Alice has created a room "Sprint 42 Planning"
    And Bob has joined the room as a guest
    When Alice adds a ticket "PROJ-7" titled "Login bug"
    And Alice starts voting on the next ticket
    And Alice votes "3"
    And Bob votes "3"
    And Alice reveals the cards
    And Alice accepts "3" story points
    Then Alice sees "PROJ-7" in the session history with "3" points
    And Bob sees "PROJ-7" in the session history with "3" points
