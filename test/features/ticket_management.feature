# Requirement: A Scrum Master needs to populate the ticket queue efficiently —
# either typing them in one at a time for ad-hoc sessions, or bulk-importing a
# Jira backlog for sprint planning. Bad imports must fail clearly so the SM
# knows what to fix.

Feature: Ticket Management
  As a Scrum Master
  I want to populate the ticket queue
  So that the team can vote on planned work efficiently

  Scenario: Scrum Master adds tickets one at a time
    Given Alice has created a room "Sprint 42 Planning"
    When Alice adds a ticket "PROJ-1" titled "First task"
    And Alice adds a ticket "PROJ-2" titled "Second task"
    And Alice adds a ticket "PROJ-3" titled "Third task"
    Then Alice sees 3 tickets in the queue

  Scenario: Scrum Master imports tickets from a Jira CSV
    Given Alice has created a room "Sprint 42 Planning"
    When Alice imports a CSV with 3 valid tickets
    Then Alice sees 3 tickets in the queue
    And Alice sees "Imported 3 tickets"

  Scenario: Import fails when a required CSV column is missing
    Given Alice has created a room "Sprint 42 Planning"
    When Alice imports a CSV missing the "Issue key" column
    Then Alice sees "Missing required columns"
    And Alice sees 0 tickets in the queue
