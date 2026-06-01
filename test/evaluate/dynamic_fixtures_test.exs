defmodule Evaluate.DynamicFixturesTest do
  use ExUnit.Case, async: false

  alias Evaluate.Benchmark.{DynamicFixtures, Fixture, FixtureGenerator, Fixtures}
  alias Research.Brief

  setup do
    DynamicFixtures.clear(:test_domain)
    DynamicFixtures.clear(:dynamic_only_domain)

    on_exit(fn ->
      DynamicFixtures.clear(:test_domain)
      DynamicFixtures.clear(:dynamic_only_domain)
    end)
  end

  # ---------------------------------------------------------------------------
  # Research.Brief
  # ---------------------------------------------------------------------------

  describe "Research.Brief" do
    test "usable?/1 returns true only for :usable_for_generation status" do
      brief = brief_fixture(%{status: :usable_for_generation})
      assert Brief.usable?(brief)

      for status <- [:draft, :verified, :stale, :archived] do
        refute Brief.usable?(brief_fixture(%{status: status})), "expected false for #{status}"
      end
    end

    test "stale?/1 returns false when no expiry" do
      refute Brief.stale?(brief_fixture(%{expires_at: nil}))
    end

    test "stale?/1 returns true when expiry is in the past" do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert Brief.stale?(brief_fixture(%{expires_at: past}))
    end

    test "stale?/1 returns false when expiry is in the future" do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      refute Brief.stale?(brief_fixture(%{expires_at: future}))
    end
  end

  # ---------------------------------------------------------------------------
  # FixtureGenerator
  # ---------------------------------------------------------------------------

  describe "FixtureGenerator.from_brief/2" do
    test "returns empty list for non-usable brief" do
      brief = brief_fixture(%{status: :draft})
      assert FixtureGenerator.from_brief(brief) == []
    end

    test "generates explain and identify fixtures from a usable brief" do
      brief = usable_brief()
      fixtures = FixtureGenerator.from_brief(brief, task_types: [:explain, :identify])

      assert length(fixtures) == 2
      assert Enum.all?(fixtures, &match?(%Fixture{}, &1))
    end

    test "skips :implement when brief has no examples" do
      brief = usable_brief(%{examples: nil})
      fixtures = FixtureGenerator.from_brief(brief, task_types: [:implement])
      assert fixtures == []
    end

    test "generates :implement when brief has examples" do
      brief = usable_brief(%{examples: [%{description: "use RLS with auth.uid()"}]})
      fixtures = FixtureGenerator.from_brief(brief, task_types: [:implement])
      assert length(fixtures) == 1
      assert hd(fixtures).tags |> Enum.member?(:implementation)
    end

    test "all generated fixtures are scoreable: false" do
      fixtures = FixtureGenerator.from_brief(usable_brief())
      assert Enum.all?(fixtures, &(&1.scoreable == false))
    end

    test "all generated fixtures are tagged :generated" do
      fixtures = FixtureGenerator.from_brief(usable_brief())
      assert Enum.all?(fixtures, &(:generated in &1.tags))
    end

    test "fixture ids are deterministic for the same brief" do
      brief = usable_brief()
      ids1 = brief |> FixtureGenerator.from_brief() |> Enum.map(& &1.id)
      ids2 = brief |> FixtureGenerator.from_brief() |> Enum.map(& &1.id)
      assert ids1 == ids2
    end

    test "fixture prompts include the brief topic" do
      brief = usable_brief(%{topic: "Row Level Security"})
      fixtures = FixtureGenerator.from_brief(brief)

      for f <- fixtures do
        assert String.contains?(f.prompt, "Row Level Security"),
               "prompt missing topic: #{f.prompt}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # DynamicFixtures store
  # ---------------------------------------------------------------------------

  describe "DynamicFixtures" do
    test "starts empty for an unknown domain" do
      assert DynamicFixtures.for_domain(:test_domain) == []
    end

    test "add/2 stores fixtures for a domain" do
      fixtures = FixtureGenerator.from_brief(usable_brief())
      :ok = DynamicFixtures.add(:test_domain, fixtures)
      assert DynamicFixtures.for_domain(:test_domain) == fixtures
    end

    test "duplicate IDs are ignored on subsequent add" do
      fixtures = FixtureGenerator.from_brief(usable_brief())
      DynamicFixtures.add(:test_domain, fixtures)
      DynamicFixtures.add(:test_domain, fixtures)
      stored = DynamicFixtures.for_domain(:test_domain)
      ids = Enum.map(stored, & &1.id)
      assert length(ids) == length(Enum.uniq(ids))
    end

    test "clear/1 removes all fixtures for a domain" do
      DynamicFixtures.add(:test_domain, FixtureGenerator.from_brief(usable_brief()))
      DynamicFixtures.clear(:test_domain)
      assert DynamicFixtures.for_domain(:test_domain) == []
    end

    test "domains/0 includes domains that have fixtures" do
      DynamicFixtures.add(:test_domain, FixtureGenerator.from_brief(usable_brief()))
      assert :test_domain in DynamicFixtures.domains()
    end
  end

  # ---------------------------------------------------------------------------
  # Fixtures registry integration
  # ---------------------------------------------------------------------------

  describe "Fixtures.for_domain/1 with dynamic fixtures" do
    test "merges static and dynamic fixtures" do
      static_count = length(Fixtures.for_domain(:elixir))

      brief = usable_brief(%{domain: :elixir, topic: "Broadway pipelines"})
      DynamicFixtures.add(:elixir, FixtureGenerator.from_brief(brief))

      merged = Fixtures.for_domain(:elixir)
      assert length(merged) > static_count
    end

    test "static IDs take precedence — dynamic duplicate is dropped" do
      %Fixture{} = static = Fixtures.for_domain(:elixir) |> hd()

      duplicate = %Fixture{static | tags: [:duplicate_test]}
      DynamicFixtures.add(:elixir, [duplicate])

      result = Fixtures.for_domain(:elixir) |> Enum.find(&(&1.id == static.id))
      refute :duplicate_test in result.tags
    end

    test "dynamic-only domain is accessible via for_domain/1" do
      brief = usable_brief(%{domain: :dynamic_only_domain, topic: "some new topic"})
      DynamicFixtures.add(:dynamic_only_domain, FixtureGenerator.from_brief(brief))

      fixtures = Fixtures.for_domain(:dynamic_only_domain)
      assert length(fixtures) > 0
    end

    test "unknown domain with no dynamic fixtures raises" do
      assert_raise ArgumentError, fn -> Fixtures.for_domain(:completely_unknown) end
    end

    test "dynamic-only domain appears in domains/0" do
      DynamicFixtures.add(:dynamic_only_domain, FixtureGenerator.from_brief(usable_brief()))
      assert :dynamic_only_domain in Fixtures.domains()
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp brief_fixture(overrides) do
    Map.merge(
      %Brief{
        id: "brief-test-0001",
        domain: :test_domain,
        topic: "GenServer timeouts",
        facts: [
          "GenServer.call/3 has a default timeout of 5000ms",
          "Timeout raises :timeout exit in the calling process",
          "The server process continues running after a call timeout"
        ],
        examples: nil,
        prohibited_patterns: ["do not use :infinity timeout in production"],
        sources: [
          %{
            kind: :official_docs,
            reference: "https://hexdocs.pm/elixir/GenServer.html",
            retrieved_at: DateTime.utc_now()
          }
        ],
        package_versions: %{"elixir" => "1.18"},
        created_at: DateTime.utc_now(),
        expires_at: nil,
        status: :draft
      },
      overrides
    )
  end

  defp usable_brief(overrides \\ %{}) do
    brief_fixture(Map.merge(%{status: :usable_for_generation}, overrides))
  end
end
