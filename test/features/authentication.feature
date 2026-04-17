# Requirement: Friction in account creation and recovery is the #1 reason
# users bounce off a tool. Registration must be one field. Magic links remove
# the password entirely. Forgot-password must work even when someone has set
# a password but doesn't remember it.

Feature: Authentication
  As a team member
  I want simple, secure ways to access my account
  So that I can join planning sessions without friction

  Scenario: A new user registers an account
    Given Charlie is on the registration page
    When Charlie registers with email "charlie@example.com"
    Then Charlie sees a message about an email being sent
    And an account exists for "charlie@example.com"

  Scenario: A returning user uses a magic login link
    Given Charlie has an account with email "charlie@example.com"
    When Charlie opens his magic login link
    Then Charlie sees a welcome confirmation for "charlie@example.com"

  Scenario: A user who forgot their password requests a recovery link
    Given Charlie has an account with email "charlie@example.com"
    And Charlie is on the login page
    When Charlie enters "charlie@example.com" in the password form
    And Charlie clicks the Forgot password link
    Then Charlie sees a message about an email being sent
