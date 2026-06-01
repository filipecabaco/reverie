defmodule Domains.PipelineReuseTest do
  @moduledoc """
  Proves that the full pipeline parameterises cleanly across domains.

  Every assertion here exercises real pipeline code with Postgres fixtures —
  no Postgres-specific branches exist in the pipeline modules themselves.
  Adding a third domain requires only a new `Domains.X` module + registry entry.
  """

  use ExUnit.Case, async: true

  alias DatasetGen.Output
  alias Domains.Registry
  alias Evaluate.Benchmark.Fixtures
  alias Evaluate.{Benchmark, FourWay}
  alias Ingest.{DatasetBuilder, Snapshot}

  @moduletag :tmp_dir

  # ---------------------------------------------------------------------------
  # Benchmark fixtures — identical API for both domains
  # ---------------------------------------------------------------------------

  describe "benchmark fixtures work identically for all domains" do
    test "each domain has benchmark fixtures with required fields" do
      for domain <- Registry.domains() do
        fixtures = Fixtures.for_domain(domain)
        assert length(fixtures) > 0, "#{domain}: no fixtures"

        for f <- fixtures do
          assert is_binary(f.prompt), "#{domain}/#{f.id}: prompt missing"
          assert is_atom(f.category), "#{domain}/#{f.id}: category missing"
          assert is_boolean(f.scoreable), "#{domain}/#{f.id}: scoreable missing"
        end
      end
    end

    test "fixture ids are unique across all domains" do
      all_ids = Registry.domains() |> Enum.flat_map(&Fixtures.for_domain/1) |> Enum.map(& &1.id)
      assert length(all_ids) == length(Enum.uniq(all_ids)), "duplicate ids across domains"
    end

    test "Postgres fixtures cover all declared categories" do
      declared = Evaluate.Benchmark.Fixtures.Postgres.categories() |> MapSet.new()
      present = Fixtures.for_domain(:postgres) |> Enum.map(& &1.category) |> MapSet.new()

      for cat <- declared do
        assert MapSet.member?(present, cat), "postgres: missing category #{cat}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Benchmark.run — same call works for both domains
  # ---------------------------------------------------------------------------

  describe "Benchmark.run/2 works for any domain" do
    test "postgres domain runs without domain-specific code" do
      responder = fn _prompt -> "SELECT 1;" end
      report = Benchmark.run(:postgres, responder)

      assert report.domain == :postgres
      assert is_float(report.compile_rate)
      assert is_float(report.test_pass_rate)
    end

    test "elixir and postgres produce structurally identical Report structs" do
      responder = fn _prompt -> "SELECT 1;" end

      elixir_report = Benchmark.run(:elixir, responder)
      postgres_report = Benchmark.run(:postgres, responder)

      assert elixir_report.__struct__ == postgres_report.__struct__
      assert Map.keys(elixir_report) == Map.keys(postgres_report)
    end
  end

  # ---------------------------------------------------------------------------
  # DatasetBuilder — domain is just a parameter
  # ---------------------------------------------------------------------------

  describe "DatasetBuilder.build/1 works for any domain" do
    test "builds a postgres dataset from generated candidates", %{tmp_dir: dir} do
      source = write_postgres_candidates(dir, 30)
      snapshot_dir = Path.join(dir, "postgres-snap")

      assert {:ok, result} =
               DatasetBuilder.build(
                 source_paths: [source],
                 snapshot_dir: snapshot_dir,
                 domain: :postgres,
                 dataset_id: "postgres-v0.1",
                 quality: [require_compiled: false, min_answer_bytes: 30]
               )

      assert result.report.total == 30
      assert result.meta[:dataset_id] == "postgres-v0.1"
      assert result.meta[:domain] == :postgres
      assert :ok = Snapshot.verify(snapshot_dir)
    end

    test "both domains produce valid, separate snapshots", %{tmp_dir: dir} do
      elixir_source = write_elixir_candidates(dir, 20)
      postgres_source = write_postgres_candidates(dir, 20)

      {:ok, elixir_result} =
        DatasetBuilder.build(
          source_paths: [elixir_source],
          snapshot_dir: Path.join(dir, "elixir-snap"),
          domain: :elixir,
          dataset_id: "elixir-v0.1"
        )

      {:ok, postgres_result} =
        DatasetBuilder.build(
          source_paths: [postgres_source],
          snapshot_dir: Path.join(dir, "postgres-snap"),
          domain: :postgres,
          dataset_id: "postgres-v0.1",
          quality: [require_compiled: false, min_answer_bytes: 30]
        )

      assert elixir_result.meta[:domain] == :elixir
      assert postgres_result.meta[:domain] == :postgres
      assert elixir_result.report.total == 20
      assert postgres_result.report.total == 20
    end
  end

  # ---------------------------------------------------------------------------
  # FourWay — identical call for any domain
  # ---------------------------------------------------------------------------

  describe "FourWay.run/2 works for any domain" do
    test "runs all four conditions for postgres domain" do
      stub = fn _prompt -> "SELECT id FROM users;" end

      responders = %{
        base: stub,
        base_retrieval: stub,
        adapter: stub,
        adapter_retrieval: stub
      }

      result = FourWay.run(:postgres, responders)

      assert result.domain == :postgres
      assert %Evaluate.Benchmark.Report{} = result.base
      assert %Evaluate.Benchmark.Report{} = result.adapter
      assert is_float(result.comparison.adapter_gain)
    end
  end

  # ---------------------------------------------------------------------------
  # Domain configs — distinct, no cross-contamination
  # ---------------------------------------------------------------------------

  describe "domain configs are independent" do
    test "elixir and postgres have different corpus paths" do
      elixir_cfg = Registry.config(:elixir)
      postgres_cfg = Registry.config(:postgres)
      assert elixir_cfg.corpus_path != postgres_cfg.corpus_path
    end

    test "elixir and postgres have different task weight distributions" do
      elixir_weights = Registry.config(:elixir).task_weights
      postgres_weights = Registry.config(:postgres).task_weights
      assert elixir_weights != postgres_weights
    end

    test "generation configs carry the correct domain" do
      for domain <- Registry.domains() do
        cfg = Registry.generation_config(domain)
        assert cfg.domain == domain
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp write_elixir_candidates(dir, n) do
    path = Path.join(dir, "elixir_candidates.jsonl")

    Enum.each(1..n, fn i ->
      Output.write(path, %{
        "messages" => [
          %{"role" => "user", "content" => "Elixir question #{i}"},
          %{"role" => "assistant", "content" => String.duplicate("Elixir answer here ", 6)}
        ],
        "meta" => %{
          "id" => "elixir-#{i}",
          "domain" => "elixir",
          "task_type" => "implement",
          "topic" => "topic-#{i}",
          "compiled" => true
        }
      })
    end)

    path
  end

  defp write_postgres_candidates(dir, n) do
    path = Path.join(dir, "postgres_candidates.jsonl")

    Enum.each(1..n, fn i ->
      Output.write(path, %{
        "messages" => [
          %{"role" => "user", "content" => "Postgres question #{i}"},
          %{"role" => "assistant", "content" => String.duplicate("SQL answer here ", 6)}
        ],
        "meta" => %{
          "id" => "postgres-#{i}",
          "domain" => "postgres",
          "task_type" => "querying",
          "topic" => "topic-#{i}",
          "compiled" => nil
        }
      })
    end)

    path
  end
end
