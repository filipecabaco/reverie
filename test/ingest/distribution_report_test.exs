defmodule Ingest.DistributionReportTest do
  use ExUnit.Case, async: true

  alias Ingest.DistributionReport

  describe "compute/1" do
    test "counts total candidates across all splits" do
      splits = %{
        train: make_candidates(10, "implement"),
        validation: make_candidates(3, "debug"),
        test: make_candidates(2, "explain"),
        regression: make_candidates(1, "implement")
      }

      report = DistributionReport.compute(splits)
      assert report.total == 16
    end

    test "records per-split counts" do
      splits = %{
        train: make_candidates(10, "implement"),
        validation: make_candidates(3, "debug"),
        test: make_candidates(2, "explain"),
        regression: make_candidates(1, "review")
      }

      report = DistributionReport.compute(splits)
      assert report.by_split.train == 10
      assert report.by_split.validation == 3
      assert report.by_split.test == 2
      assert report.by_split.regression == 1
    end

    test "computes task type distribution" do
      splits = %{
        train: make_candidates(5, "implement") ++ make_candidates(3, "debug"),
        validation: [],
        test: [],
        regression: []
      }

      report = DistributionReport.compute(splits)
      assert report.task_type_dist["implement"] == 5
      assert report.task_type_dist["debug"] == 3
    end

    test "computes compile rate" do
      compiled = Enum.map(1..8, fn i -> candidate(i, compiled: true) end)
      not_compiled = Enum.map(9..10, fn i -> candidate(i, compiled: false) end)

      splits = %{train: compiled ++ not_compiled, validation: [], test: [], regression: []}
      report = DistributionReport.compute(splits)
      assert report.compile_rate == 80.0
    end

    test "ignores nil compiled values in rate calculation" do
      with_compiled = [candidate(1, compiled: true), candidate(2, compiled: true)]
      without_compiled = [candidate(3, compiled: nil)]

      splits = %{
        train: with_compiled ++ without_compiled,
        validation: [],
        test: [],
        regression: []
      }

      report = DistributionReport.compute(splits)
      assert report.compile_rate == 100.0
    end

    test "counts unique topics" do
      t1 = candidate(1, topic: "GenServer")
      t2 = candidate(2, topic: "GenServer")
      t3 = candidate(3, topic: "Agent")

      splits = %{train: [t1, t2, t3], validation: [], test: [], regression: []}
      report = DistributionReport.compute(splits)
      assert report.topic_coverage == 2
    end

    test "counts unique briefs" do
      b1a = candidate(1, brief_id: "brief-1")
      b1b = candidate(2, brief_id: "brief-1")
      b2 = candidate(3, brief_id: "brief-2")
      no_brief = candidate(4, brief_id: nil)

      splits = %{train: [b1a, b1b, b2, no_brief], validation: [], test: [], regression: []}
      report = DistributionReport.compute(splits)
      assert report.brief_coverage == 2
    end

    test "handles completely empty splits" do
      splits = %{train: [], validation: [], test: [], regression: []}
      report = DistributionReport.compute(splits)
      assert report.total == 0
      assert report.compile_rate == 0.0
    end
  end

  describe "summary/1" do
    test "returns a non-empty string with key metrics" do
      splits = %{
        train: make_candidates(10, "implement"),
        validation: make_candidates(2, "debug"),
        test: make_candidates(2, "explain"),
        regression: make_candidates(1, "review")
      }

      summary = splits |> DistributionReport.compute() |> DistributionReport.summary()
      assert is_binary(summary)
      assert String.contains?(summary, "Total candidates")
      assert String.contains?(summary, "train")
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp make_candidates(n, task_type) do
    Enum.map(1..n, fn i -> candidate(i, task_type: task_type) end)
  end

  defp candidate(id, opts) do
    %{
      "messages" => [
        %{"role" => "user", "content" => "Question #{id}"},
        %{"role" => "assistant", "content" => "Answer #{id}"}
      ],
      "meta" => %{
        "id" => "id-#{id}",
        "task_type" => Keyword.get(opts, :task_type, "implement"),
        "compiled" => Keyword.get(opts, :compiled, true),
        "tests_passed" => Keyword.get(opts, :tests_passed, nil),
        "topic" => Keyword.get(opts, :topic, "topic-#{id}"),
        "brief_id" => Keyword.get(opts, :brief_id, nil)
      }
    }
  end
end
