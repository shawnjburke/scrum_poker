# Requirement: Different teams estimate differently. Numeric Fibonacci is the
# default for engineering. T-shirt sizes work for business teams. The Dogs deck
# uses relative metaphors to break the habit of mentally mapping points to time.

Feature: Card Decks
  As a Scrum Master
  I want to choose an estimation deck that fits my team
  So that voting matches how my team thinks about complexity

  Scenario: Fibonacci deck offers standard story point values
    Given Alice has created a room "Sprint 42" with the "fibonacci" deck
    When Alice adds a ticket "PROJ-1" titled "First task"
    And Alice starts voting on the next ticket
    Then Alice sees the card "5" available
    And Alice sees the card "13" available
    And Alice sees the card "?" available

  Scenario: T-shirt deck offers size labels instead of numbers
    Given Alice has created a room "Sprint 42" with the "tshirt" deck
    When Alice adds a ticket "PROJ-1" titled "First task"
    And Alice starts voting on the next ticket
    Then Alice sees the card "M" available
    And Alice sees the card "XXL" available

  Scenario: Dogs deck offers breed names so the team thinks in relative size
    Given Alice has created a room "Sprint 42" with the "dogs" deck
    When Alice adds a ticket "PROJ-1" titled "First task"
    And Alice starts voting on the next ticket
    Then Alice sees the card "Chihuahua" available
    And Alice sees the card "Saint Bernard" available
