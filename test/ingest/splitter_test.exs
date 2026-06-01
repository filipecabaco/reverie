defmodule Ingest.SplitterTest do
  use ExUnit.Case, async: true

  alias Ingest.Splitter

  describe "split/3 — basic splitting" do
    test "distributes candidates across all four splits" do
      candidates = make_candidates(100)
      {:ok, splits, _} = Splitter.split(candidates)

      assert map_size(splits) == 4
      assert Enum.member?(Map.keys(splits), :train)
      assert Enum.member?(Map.keys(splits), :validation)
      assert Enum.member?(Map.keys(splits), :test)
      assert Enum.member?(Map.keys(splits), :regression)
    end

    test "total across splits equals total after dedup" do
      candidates = make_candidates(100)
      {:ok, splits, dedup_stats} = Splitter.split(candidates)
      split_total = splits |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
      assert split_total == dedup_stats.after
    end

    test "train gets the largest share by default" do
      candidates = make_candidates(100)
      {:ok, splits, _} = Splitter.split(candidates)
      assert length(splits.train) > length(splits.validation)
      assert length(splits.train) > length(splits.test)
    end

    test "respects custom ratios" do
      candidates = make_candidates(200)

      ratios = %{train: 0.50, validation: 0.20, test: 0.20, regression: 0.10}
      {:ok, splits, _} = Splitter.split(candidates, ratios)

      total = splits |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
      assert total == 200
      assert length(splits.train) > length(splits.test)
    end

    test "is deterministic with the same seed" do
      candidates = make_candidates(50)
      {:ok, s1, _} = Splitter.split(candidates, Splitter.default_ratios(), seed: 7)
      {:ok, s2, _} = Splitter.split(candidates, Splitter.default_ratios(), seed: 7)

      ids1 = Enum.map(s1.train, &get_id/1)
      ids2 = Enum.map(s2.train, &get_id/1)
      assert ids1 == ids2
    end

    test "produces different splits with different seeds" do
      candidates = make_candidates(100)
      {:ok, s1, _} = Splitter.split(candidates, Splitter.default_ratios(), seed: 1)
      {:ok, s2, _} = Splitter.split(candidates, Splitter.default_ratios(), seed: 99)

      ids1 = Enum.map(s1.train, &get_id/1) |> MapSet.new()
      ids2 = Enum.map(s2.train, &get_id/1) |> MapSet.new()
      refute ids1 == ids2
    end
  end

  describe "split/3 — deduplication" do
    test "removes exact instruction duplicates" do
      base = make_candidate("duplicate-topic", 1)
      dup = make_candidate("duplicate-topic", 1)
      others = make_candidates(10)

      {:ok, splits, dedup_stats} = Splitter.split([base, dup | others])
      total = splits |> Map.values() |> Enum.map(&length/1) |> Enum.sum()

      assert dedup_stats.dropped_as_duplicates == 1
      assert total == 11
    end

    test "removes duplicate code regardless of instruction" do
      c1 = make_candidate_with_code("Different question A", "defmodule X do\n  def f, do: 1\nend")
      c2 = make_candidate_with_code("Different question B", "defmodule X do\n  def f, do: 1\nend")
      others = make_candidates(5)

      {:ok, _, dedup_stats} = Splitter.split([c1, c2 | others])
      assert dedup_stats.dropped_as_duplicates == 1
    end

    test "preserves candidates with different code" do
      c1 = make_candidate_with_code("Question A", "def foo, do: 1")
      c2 = make_candidate_with_code("Question B", "def bar, do: 2")

      {:ok, _, dedup_stats} = Splitter.split([c1, c2])
      assert dedup_stats.dropped_as_duplicates == 0
    end
  end

  describe "split/3 — brief-group integrity" do
    test "candidates from the same brief end up in the same split" do
      brief_id = "brief-abc"
      group = Enum.map(1..5, fn i -> make_candidate_with_brief("topic-#{i}", brief_id) end)
      others = make_candidates(100)

      {:ok, splits, _} = Splitter.split(group ++ others, Splitter.default_ratios(), seed: 42)

      group_ids = Enum.map(group, &get_id/1) |> MapSet.new()

      split_assignments =
        splits
        |> Enum.flat_map(fn {split, candidates} ->
          candidates
          |> Enum.filter(&(get_id(&1) in group_ids))
          |> Enum.map(fn _ -> split end)
        end)
        |> Enum.uniq()

      assert length(split_assignments) == 1,
             "Brief group was split across #{inspect(split_assignments)}"
    end
  end

  describe "split/3 — edge cases" do
    test "handles empty input" do
      {:ok, splits, dedup_stats} = Splitter.split([])
      assert dedup_stats.after == 0
      assert Enum.all?(Map.values(splits), &(&1 == []))
    end

    test "handles fewer candidates than splits" do
      {:ok, splits, _} = Splitter.split(make_candidates(2))
      total = splits |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
      assert total == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp make_candidates(n) do
    Enum.map(1..n, &make_candidate("topic-#{&1}", &1))
  end

  defp make_candidate(topic, id) do
    %{
      "messages" => [
        %{"role" => "user", "content" => "Question about #{topic} number #{id}"},
        %{"role" => "assistant", "content" => String.duplicate("answer ", 20)}
      ],
      "meta" => %{
        "id" => "id-#{topic}-#{id}",
        "topic" => topic,
        "task_type" => "implement",
        "compiled" => true
      }
    }
  end

  defp make_candidate_with_code(instruction, code) do
    %{
      "messages" => [
        %{"role" => "user", "content" => instruction},
        %{"role" => "assistant", "content" => "Here: ```#{code}```"}
      ],
      "meta" => %{
        "id" => :crypto.hash(:sha256, instruction) |> Base.encode16(case: :lower),
        "code" => code,
        "compiled" => true
      }
    }
  end

  defp make_candidate_with_brief(topic, brief_id) do
    %{
      "messages" => [
        %{"role" => "user", "content" => "Question about #{topic}"},
        %{"role" => "assistant", "content" => String.duplicate("answer ", 20)}
      ],
      "meta" => %{
        "id" => "id-brief-#{topic}-#{brief_id}",
        "topic" => topic,
        "brief_id" => brief_id,
        "compiled" => true
      }
    }
  end

  defp get_id(c), do: c["meta"]["id"] || c[:meta][:id]
end
