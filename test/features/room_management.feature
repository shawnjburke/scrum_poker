# Requirement: A Scrum Master needs to set up a focused space for a planning
# session, share access easily with the team, and formally close it when done.

Feature: Room Management
  As a Scrum Master
  I want to create and manage planning sessions
  So that my team can estimate together in a focused space

  Scenario: Scrum Master creates a room with a chosen card deck
    Given Alice is logged in as a Scrum Master
    When Alice creates a room "Sprint 42 Planning" using the "tshirt" deck
    Then Alice sees the room "Sprint 42 Planning"
    And Alice sees a unique room code

  Scenario: A guest joins a room using just the code
    Given Alice has created a room "Sprint 42 Planning"
    When Bob joins the room as a guest named "Bob"
    Then Bob sees the room "Sprint 42 Planning"
    And Alice sees "Bob" in the participant list

  Scenario: Scrum Master ends a session and the room is locked
    Given Alice has created a room "Sprint 42 Planning"
    When Alice adds a ticket "PROJ-1" titled "First task"
    And Alice starts voting on the next ticket
    And Alice votes "5"
    And Alice reveals the cards
    And Alice accepts "5" story points
    And Alice ends the session
    Then Alice sees "Session Complete"
