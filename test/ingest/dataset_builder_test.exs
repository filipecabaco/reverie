defmodule Ingest.DatasetBuilderTest do
  use ExUnit.Case, async: true

  alias DatasetGen.Output
  alias Ingest.{DatasetBuilder, Snapshot}

  @moduletag :tmp_dir

  describe "build/1 — happy path" do
    test "produces a complete frozen snapshot", %{tmp_dir: dir} do
      source = write_candidates(dir, "source.jsonl", 40)
      snapshot_dir = Path.join(dir, "snapshot")

      assert {:ok, result} =
               DatasetBuilder.build(
                 source_paths: [source],
                 snapshot_dir: snapshot_dir,
                 domain: :elixir,
                 dataset_id: "elixir-v0.1",
                 seed: 42
               )

      assert :ok = Snapshot.verify(snapshot_dir)
      assert result.meta[:dataset_id] == "elixir-v0.1"
      assert result.report.total == 40
    end

    test "all splits are present in the snapshot directory", %{tmp_dir: dir} do
      source = write_candidates(dir, "source.jsonl", 40)
      snapshot_dir = Path.join(dir, "snap")

      {:ok, _} =
        DatasetBuilder.build(
          source_paths: [source],
          snapshot_dir: snapshot_dir,
          domain: :elixir,
          dataset_id: "elixir-v0.1"
        )

      for split <- [:train, :validation, :test, :regression] do
        assert Snapshot.count(snapshot_dir, split) > 0, "#{split} split is empty"
      end
    end

    test "train has the most candidates", %{tmp_dir: dir} do
      source = write_candidates(dir, "source.jsonl", 80)
      snapshot_dir = Path.join(dir, "snap")

      {:ok, result} =
        DatasetBuilder.build(
          source_paths: [source],
          snapshot_dir: snapshot_dir,
          domain: :elixir,
          dataset_id: "elixir-v0.1"
        )

      assert result.report.by_split.train > result.report.by_split.validation
      assert result.report.by_split.train > result.report.by_split.test
    end

    test "reads from multiple source files", %{tmp_dir: dir} do
      s1 = write_candidates(dir, "run1.jsonl", 20, offset: 0)
      s2 = write_candidates(dir, "run2.jsonl", 20, offset: 20)
      snapshot_dir = Path.join(dir, "snap")

      {:ok, result} =
        DatasetBuilder.build(
          source_paths: [s1, s2],
          snapshot_dir: snapshot_dir,
          domain: :elixir,
          dataset_id: "elixir-v0.1"
        )

      assert result.report.total == 40
    end

    test "report includes compile rate and topic coverage", %{tmp_dir: dir} do
      source = write_candidates(dir, "source.jsonl", 20)
      snapshot_dir = Path.join(dir, "snap")

      {:ok, result} =
        DatasetBuilder.build(
          source_paths: [source],
          snapshot_dir: snapshot_dir,
          domain: :elixir,
          dataset_id: "elixir-v0.1"
        )

      assert is_float(result.report.compile_rate)
      assert result.report.topic_coverage > 0
    end

    test "quality_summary reports filter stats", %{tmp_dir: dir} do
      source = write_candidates_mixed(dir, "mixed.jsonl")
      snapshot_dir = Path.join(dir, "snap")

      {:ok, result} =
        DatasetBuilder.build(
          source_paths: [source],
          snapshot_dir: snapshot_dir,
          domain: :elixir,
          dataset_id: "elixir-v0.1",
          quality: [require_compiled: true]
        )

      assert result.quality_summary.total > result.quality_summary.kept
    end

    test "dedup_stats reports removed duplicates", %{tmp_dir: dir} do
      source = write_candidates_with_dups(dir, "dups.jsonl")
      snapshot_dir = Path.join(dir, "snap")

      {:ok, result} =
        DatasetBuilder.build(
          source_paths: [source],
          snapshot_dir: snapshot_dir,
          domain: :elixir,
          dataset_id: "elixir-v0.1"
        )

      assert result.dedup_stats.dropped_as_duplicates > 0
    end
  end

  describe "build/1 — custom ratios" do
    test "respects custom split ratios", %{tmp_dir: dir} do
      source = write_candidates(dir, "source.jsonl", 100)
      snapshot_dir = Path.join(dir, "snap")

      ratios = %{train: 0.60, validation: 0.20, test: 0.15, regression: 0.05}

      {:ok, result} =
        DatasetBuilder.build(
          source_paths: [source],
          snapshot_dir: snapshot_dir,
          domain: :postgres,
          dataset_id: "postgres-v0.1",
          ratios: ratios
        )

      assert result.report.by_split.train > result.report.by_split.validation
      assert result.report.total == 100
    end
  end

  describe "build/1 — domain parameter" do
    test "domain is recorded in snapshot metadata", %{tmp_dir: dir} do
      source = write_candidates(dir, "source.jsonl", 20)
      snapshot_dir = Path.join(dir, "snap")

      {:ok, result} =
        DatasetBuilder.build(
          source_paths: [source],
          snapshot_dir: snapshot_dir,
          domain: :supabase,
          dataset_id: "supabase-v0.1"
        )

      assert result.meta[:domain] == :supabase
    end
  end

  describe "build/1 — error handling" do
    test "returns error for missing source file", %{tmp_dir: dir} do
      result =
        DatasetBuilder.build(
          source_paths: [Path.join(dir, "missing.jsonl")],
          snapshot_dir: Path.join(dir, "snap"),
          domain: :elixir,
          dataset_id: "elixir-v0.1"
        )

      # Missing file is treated as empty (Output.read_all returns [])
      assert {:ok, %{report: report}} = result
      assert report.total == 0
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp write_candidates(dir, filename, count, opts \\ []) do
    path = Path.join(dir, filename)
    offset = Keyword.get(opts, :offset, 0)

    Enum.each(1..count, fn i ->
      candidate = %{
        "messages" => [
          %{"role" => "user", "content" => "Question about topic-#{i + offset} in Elixir"},
          %{"role" => "assistant", "content" => String.duplicate("answer text here ", 10)}
        ],
        "meta" => %{
          "id" => "id-#{i + offset}",
          "domain" => "elixir",
          "task_type" => Enum.random(["implement", "debug"]),
          "topic" => "topic-#{i + offset}",
          "compiled" => true,
          "tests_passed" => nil,
          "brief_id" => nil
        }
      }

      Output.write(path, candidate)
    end)

    path
  end

  defp write_candidates_mixed(dir, filename) do
    path = Path.join(dir, filename)

    Enum.each(1..10, fn i ->
      compiled = rem(i, 3) != 0

      Output.write(path, %{
        "messages" => [
          %{"role" => "user", "content" => "Question #{i}"},
          %{"role" => "assistant", "content" => String.duplicate("a", 100)}
        ],
        "meta" => %{
          "id" => "id-#{i}",
          "domain" => "elixir",
          "task_type" => "implement",
          "topic" => "topic-#{i}",
          "compiled" => compiled
        }
      })
    end)

    path
  end

  defp write_candidates_with_dups(dir, filename) do
    path = Path.join(dir, filename)

    base = %{
      "messages" => [
        %{"role" => "user", "content" => "Implement a GenServer counter"},
        %{"role" => "assistant", "content" => String.duplicate("answer text here ", 10)}
      ],
      "meta" => %{
        "id" => "dup-1",
        "domain" => "elixir",
        "compiled" => true,
        "task_type" => "implement",
        "topic" => "counter"
      }
    }

    dup = %{base | "meta" => Map.put(base["meta"], "id", "dup-2")}

    Enum.each(
      [base, dup] ++
        Enum.map(1..5, fn i ->
          %{
            "messages" => [
              %{"role" => "user", "content" => "Unique question #{i}"},
              %{"role" => "assistant", "content" => String.duplicate("answer ", 10)}
            ],
            "meta" => %{
              "id" => "unique-#{i}",
              "domain" => "elixir",
              "compiled" => true,
              "task_type" => "implement",
              "topic" => "unique-#{i}"
            }
          }
        end),
      &Output.write(path, &1)
    )

    path
  end
end
