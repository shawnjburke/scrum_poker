# Requirement: Once tickets are estimated, the team needs a record of what was
# decided — visible during the session and exportable afterward for sprint
# planning, capacity reports, and traceability.

Feature: Session History
  As a Scrum Master
  I want a running record of every accepted estimate
  So that I can capture the team's decisions and share them after the session

  Scenario: Multiple accepted tickets accumulate in the session history
    Given Alice has created a room "Sprint 42 Planning"
    When Alice adds a ticket "PROJ-1" titled "First task"
    And Alice starts voting on the next ticket
    And Alice votes "5"
    And Alice reveals the cards
    And Alice accepts "5" story points
    And Alice adds a ticket "PROJ-2" titled "Second task"
    And Alice starts voting on the next ticket
    And Alice votes "8"
    And Alice reveals the cards
    And Alice accepts "8" story points
    Then Alice sees "PROJ-1" in the session history with "5" points
    And Alice sees "PROJ-2" in the session history with "8" points

  Scenario: Session history is downloadable as a CSV
    Given Alice has created a room "Sprint 42 Planning"
    When Alice adds a ticket "PROJ-1" titled "Login bug"
    And Alice starts voting on the next ticket
    And Alice votes "3"
    And Alice reveals the cards
    And Alice accepts "3" story points
    And Alice downloads the history CSV
    Then the CSV includes "PROJ-1"
    And the CSV includes "Login bug"
    And the CSV includes "3"
