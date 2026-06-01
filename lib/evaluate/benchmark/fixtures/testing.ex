defmodule Evaluate.Benchmark.Fixtures.Testing do
  @behaviour Evaluate.Benchmark.Domain

  alias Evaluate.Benchmark.Fixture

  @impl true
  def name, do: "Testing"

  @impl true
  def categories do
    [:strategy, :unit, :integration, :property_based, :mocking, :coverage, :debugging]
  end

  @impl true
  def fixtures do
    [
      %Fixture{
        id: "test-strategy-001",
        category: :strategy,
        difficulty: :medium,
        prompt: """
        You are adding a payment processing feature. Describe your full testing strategy:
        which layers you test (unit, integration, contract, e2e), what you mock vs what
        you hit for real, how you handle test data for financial amounts, and what you
        do about the third-party payment provider. Include the rationale for each choice.
        """,
        test_code: nil,
        tags: [:strategy, :integration, :mocking, :explanation],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "test-unit-001",
        category: :unit,
        difficulty: :easy,
        prompt: """
        Write ExUnit tests for an `EmailValidator` module with `valid?/1` that returns
        true for well-formed email addresses and false otherwise. Cover: valid address,
        missing @, missing domain, missing TLD, leading/trailing spaces,
        empty string, and an address with a subdomain.
        """,
        test_code: nil,
        tags: [:unit, :exunit, :boundary_testing],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "test-integration-001",
        category: :integration,
        difficulty: :medium,
        prompt: """
        You have an Elixir Phoenix controller that creates a user, sends a welcome email
        (via a third-party service), and returns 201. Write an integration test using
        `Phoenix.ConnTest` that: hits the real database, stubs only the email service,
        asserts the database row was created, and asserts the email stub was called once
        with the correct address. Explain your stub/mock choice.
        """,
        test_code: nil,
        tags: [:integration, :phoenix, :mocking, :database],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "test-property-001",
        category: :property_based,
        difficulty: :medium,
        prompt: """
        Write property-based tests using StreamData for a `Money.add/2` function that
        adds two monetary values represented as integer cents. Properties to verify:
        commutativity, associativity, identity element (adding zero), and that the
        result is never negative when both inputs are non-negative.
        """,
        test_code: nil,
        tags: [:property_based, :stream_data, :invariants],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "test-mock-001",
        category: :mocking,
        difficulty: :medium,
        prompt: """
        Explain the difference between a mock, a stub, a spy, and a fake in testing.
        For each, give a concrete Elixir example (using Mox or plain modules) and
        describe when it is the right tool. When does heavy mocking become a test-quality
        anti-pattern and what refactoring fixes it?
        """,
        test_code: nil,
        tags: [:mocking, :stubs, :test_doubles, :explanation],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "test-coverage-001",
        category: :coverage,
        difficulty: :medium,
        prompt: """
        Your CI reports 85% line coverage. A senior engineer says "coverage looks good"
        but a critical bug just shipped. What does line coverage miss? Describe three
        scenarios where 85% coverage provides false confidence, and what complementary
        metrics or techniques you would add to the pipeline.
        """,
        test_code: nil,
        tags: [:coverage, :quality, :explanation],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "test-debug-001",
        category: :debugging,
        difficulty: :easy,
        prompt: """
        A test that passes locally fails intermittently in CI. List your diagnostic
        steps in order. What are the five most common causes of flaky tests in Elixir
        projects specifically, and what is the fix for each?
        """,
        test_code: nil,
        tags: [:debugging, :flaky_tests, :ci, :explanation],
        scoreable: false,
        sandbox_profile: nil
      }
    ]
  end
end
