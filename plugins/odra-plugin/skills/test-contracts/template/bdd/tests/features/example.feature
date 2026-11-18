# A sample that proves the test setup works. Delete it once the project has features of its own.
Feature: Sending CSPR
  CSPR moves between accounts without any contract.

  Background:
    Given Alice has 100 CSPR
    And Bob has 0 CSPR

  Scenario: A transfer moves CSPR from the sender to the recipient
    When Alice sends 2.5 CSPR to Bob
    Then Alice has 97.5 CSPR
    And Bob has 2.5 CSPR

  Scenario: An action that may fail is tried, and its outcome checked
    When Alice tries to send 1 CSPR to Bob
    Then it succeeds
    And Bob has 1 CSPR

  Scenario: Time passing changes no balance
    When 3 days pass
    Then Alice has 100 CSPR
