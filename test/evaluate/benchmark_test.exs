defmodule Evaluate.BenchmarkTest do
  use ExUnit.Case, async: true

  alias Evaluate.Benchmark
  alias Evaluate.Benchmark.{Fixture, Fixtures, Report}

  describe "Fixtures.domains/0" do
    test "returns all registered domains" do
      domains = Fixtures.domains()
      assert :elixir in domains
      assert :postgres in domains
      assert :supabase in domains
      assert :typescript in domains
      assert :testing in domains
      assert :security in domains
      assert :project_management in domains
    end
  end

  describe "Fixtures.for_domain/1" do
    test "returns fixtures for each registered domain" do
      for domain <- Fixtures.domains() do
        fixtures = Fixtures.for_domain(domain)
        assert length(fixtures) > 0, "#{domain}: expected fixtures, got none"
        assert Enum.all?(fixtures, &match?(%Fixture{}, &1)), "#{domain}: non-Fixture struct found"
      end
    end

    test "raises on unknown domain" do
      assert_raise ArgumentError, fn -> Fixtures.for_domain(:unknown) end
    end

    test "all fixtures across all domains have required fields" do
      for f <- Fixtures.all() do
        assert is_binary(f.id), "#{f.id}: id must be a string"
        assert is_atom(f.category), "#{f.id}: category must be an atom"
        assert is_atom(f.difficulty), "#{f.id}: difficulty must be an atom"
        assert is_binary(f.prompt), "#{f.id}: prompt must be a string"
        assert is_boolean(f.scoreable), "#{f.id}: scoreable must be a boolean"
        assert is_list(f.tags), "#{f.id}: tags must be a list"
      end
    end

    test "scoreable fixtures always have test_code" do
      for f <- Fixtures.all(), f.scoreable do
        assert is_binary(f.test_code), "#{f.id}: scoreable fixture must have test_code"
        assert f.test_code != "", "#{f.id}: test_code must not be empty"
      end
    end

    test "fixture ids are unique across all domains" do
      ids = Fixtures.all() |> Enum.map(& &1.id)
      assert length(ids) == length(Enum.uniq(ids)), "duplicate fixture ids detected"
    end

    test "each domain's fixtures use only that domain's declared categories" do
      for domain <- Fixtures.domains() do
        valid = Fixtures.categories(domain) |> MapSet.new()

        for f <- Fixtures.for_domain(domain) do
          assert MapSet.member?(valid, f.category),
                 "#{f.id}: category #{inspect(f.category)} not in #{domain}'s declared categories"
        end
      end
    end
  end

  describe "Fixtures.Elixir specifics" do
    test "covers all required Elixir categories" do
      present = Fixtures.for_domain(:elixir) |> Enum.map(& &1.category) |> MapSet.new()
      required = ~w(pattern_matching genserver supervision ecto exunit otp debugging)a

      for cat <- required do
        assert MapSet.member?(present, cat), "missing Elixir category: #{cat}"
      end
    end

    test "at least half of Elixir fixtures are sandbox-scoreable" do
      fixtures = Fixtures.for_domain(:elixir)
      scoreable = Enum.count(fixtures, & &1.scoreable)
      assert scoreable >= div(length(fixtures), 2)
    end
  end

  describe "Benchmark.score/2" do
    test "skips non-scoreable fixtures without calling sandbox" do
      fixture = %Fixture{
        id: "test-ns-001",
        category: :explanation,
        difficulty: :easy,
        prompt: "explain something",
        test_code: nil,
        tags: [],
        scoreable: false,
        sandbox_profile: nil
      }

      assert {:ok, score} = Benchmark.score(fixture, "any response")
      assert score.skipped == true
      assert score.compiled == nil
      assert score.tests_passed == nil
    end
  end

  describe "Report.build/2" do
    test "calculates rates correctly" do
      scores = [
        %{
          fixture_id: "a",
          category: :pattern_matching,
          compiled: true,
          tests_passed: true,
          skipped: false
        },
        %{
          fixture_id: "b",
          category: :pattern_matching,
          compiled: true,
          tests_passed: false,
          skipped: false
        },
        %{
          fixture_id: "c",
          category: :genserver,
          compiled: false,
          tests_passed: false,
          skipped: false
        },
        %{
          fixture_id: "d",
          category: :explanation,
          compiled: nil,
          tests_passed: nil,
          skipped: true
        }
      ]

      report = Report.build(:elixir, scores)
      assert report.total == 4
      assert report.scoreable_count == 3
      assert report.compile_rate == Float.round(2 / 3 * 100, 1)
      assert report.test_pass_rate == Float.round(1 / 3 * 100, 1)
    end

    test "handles all-skipped gracefully" do
      scores = [
        %{
          fixture_id: "a",
          category: :explanation,
          compiled: nil,
          tests_passed: nil,
          skipped: true
        }
      ]

      report = Report.build(:elixir, scores)
      assert report.compile_rate == 0.0
      assert report.test_pass_rate == 0.0
    end

    test "groups scores by category" do
      scores = [
        %{
          fixture_id: "a",
          category: :pattern_matching,
          compiled: true,
          tests_passed: true,
          skipped: false
        },
        %{
          fixture_id: "b",
          category: :genserver,
          compiled: true,
          tests_passed: false,
          skipped: false
        }
      ]

      report = Report.build(:elixir, scores)
      assert Map.has_key?(report.by_category, :pattern_matching)
      assert Map.has_key?(report.by_category, :genserver)
    end
  end

  describe "Report.summary/1" do
    test "includes domain name and rates" do
      scores = [
        %{
          fixture_id: "a",
          category: :pattern_matching,
          compiled: true,
          tests_passed: true,
          skipped: false
        }
      ]

      summary = Report.build(:elixir, scores) |> Report.summary()
      assert String.contains?(summary, "elixir")
      assert String.contains?(summary, "%")
    end
  end
end
