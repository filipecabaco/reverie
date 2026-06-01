defmodule Ingest.QualityFilterTest do
  use ExUnit.Case, async: true

  alias Ingest.QualityFilter

  describe "filter/2 — defaults" do
    test "passes candidates where compiled is true" do
      candidates = [candidate(%{"compiled" => true}), candidate(%{"compiled" => false})]
      {:ok, kept, _} = QualityFilter.filter(candidates)
      assert length(kept) == 1
      assert hd(kept)["meta"]["compiled"] == true
    end

    test "passes candidates where compiled is nil (non-code task)" do
      c = candidate(%{"compiled" => nil})
      {:ok, kept, _} = QualityFilter.filter([c])
      assert length(kept) == 1
    end

    test "drops candidates with answer shorter than min_answer_bytes" do
      short = candidate_with_answer("Hi.")
      long = candidate_with_answer(String.duplicate("a", 100))
      {:ok, kept, _} = QualityFilter.filter([short, long])
      assert length(kept) == 1
    end

    test "returns summary with total, kept, dropped, drop_rate" do
      candidates = [candidate(%{"compiled" => true}), candidate(%{"compiled" => false})]
      {:ok, _, summary} = QualityFilter.filter(candidates)
      assert summary.total == 2
      assert summary.kept == 1
      assert summary.dropped == 1
      assert is_float(summary.drop_rate)
    end
  end

  describe "filter/2 — :require_compiled option" do
    test "false disables compile gate" do
      c = candidate(%{"compiled" => false})
      {:ok, kept, _} = QualityFilter.filter([c], require_compiled: false)
      assert length(kept) == 1
    end
  end

  describe "filter/2 — :require_tests_pass option" do
    test "drops candidates where tests_passed is false" do
      fail = candidate(%{"compiled" => true, "tests_passed" => false})
      pass = candidate(%{"compiled" => true, "tests_passed" => true})
      {:ok, kept, _} = QualityFilter.filter([fail, pass], require_tests_pass: true)
      assert length(kept) == 1
      assert hd(kept)["meta"]["tests_passed"] == true
    end

    test "passes nil tests_passed (no test code)" do
      c = candidate(%{"compiled" => true, "tests_passed" => nil})
      {:ok, kept, _} = QualityFilter.filter([c], require_tests_pass: true)
      assert length(kept) == 1
    end
  end

  describe "filter/2 — :allowed_task_types option" do
    test "keeps only allowed task types" do
      impl = candidate(%{"compiled" => true, "task_type" => "implement"})
      debug = candidate(%{"compiled" => true, "task_type" => "debug"})
      {:ok, kept, _} = QualityFilter.filter([impl, debug], allowed_task_types: [:implement])
      assert length(kept) == 1
      assert hd(kept)["meta"]["task_type"] == "implement"
    end
  end

  describe "filter/2 — :custom option" do
    test "applies a custom predicate" do
      c1 = candidate(%{"compiled" => true, "topic" => "GenServer"})
      c2 = candidate(%{"compiled" => true, "topic" => "Agent"})

      custom = fn c -> c["meta"]["topic"] == "GenServer" end
      {:ok, kept, _} = QualityFilter.filter([c1, c2], custom: custom)
      assert length(kept) == 1
    end
  end

  describe "filter/2 — empty input" do
    test "handles empty list" do
      {:ok, kept, summary} = QualityFilter.filter([])
      assert kept == []
      assert summary.total == 0
      assert summary.drop_rate == 0.0
    end
  end

  defp candidate(meta_overrides) do
    %{
      "messages" => [
        %{"role" => "user", "content" => "Question about Elixir"},
        %{"role" => "assistant", "content" => String.duplicate("a", 100)}
      ],
      "meta" => Map.merge(%{"compiled" => true, "task_type" => "implement"}, meta_overrides)
    }
  end

  defp candidate_with_answer(answer) do
    %{
      "messages" => [
        %{"role" => "user", "content" => "Q"},
        %{"role" => "assistant", "content" => answer}
      ],
      "meta" => %{"compiled" => true}
    }
  end
end
