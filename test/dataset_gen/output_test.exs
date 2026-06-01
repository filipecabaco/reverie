defmodule DatasetGen.OutputTest do
  use ExUnit.Case, async: true

  alias DatasetGen.Output

  @moduletag :tmp_dir

  describe "write/2 and read_all/1" do
    test "writes one candidate and reads it back", %{tmp_dir: dir} do
      path = Path.join(dir, "out.jsonl")
      candidate = sample_candidate("id-001")

      Output.write(path, candidate)

      [read_back] = path |> Output.read_all() |> Enum.to_list()
      assert read_back["meta"]["id"] == "id-001"
    end

    test "appends multiple candidates in order", %{tmp_dir: dir} do
      path = Path.join(dir, "out.jsonl")

      Output.write(path, sample_candidate("id-001"))
      Output.write(path, sample_candidate("id-002"))
      Output.write(path, sample_candidate("id-003"))

      ids = path |> Output.read_all() |> Enum.map(& &1["meta"]["id"])
      assert ids == ["id-001", "id-002", "id-003"]
    end

    test "creates parent directories automatically", %{tmp_dir: dir} do
      path = Path.join([dir, "deep", "nested", "out.jsonl"])
      Output.write(path, sample_candidate("id-001"))
      assert File.exists?(path)
    end

    test "read_all returns empty stream for missing file", %{tmp_dir: dir} do
      path = Path.join(dir, "nonexistent.jsonl")
      assert [] = Output.read_all(path) |> Enum.to_list()
    end
  end

  describe "write_batch/2" do
    test "writes all candidates in a single file open", %{tmp_dir: dir} do
      path = Path.join(dir, "batch.jsonl")
      candidates = Enum.map(1..5, &sample_candidate("id-#{&1}"))

      Output.write_batch(path, candidates)

      ids = path |> Output.read_all() |> Enum.map(& &1["meta"]["id"])
      assert length(ids) == 5
      assert "id-1" in ids
      assert "id-5" in ids
    end

    test "write_batch with empty list creates an empty file", %{tmp_dir: dir} do
      path = Path.join(dir, "empty.jsonl")
      Output.write_batch(path, [])
      assert Output.count(path) == 0
    end
  end

  describe "count/1" do
    test "returns 0 for a missing file", %{tmp_dir: dir} do
      assert Output.count(Path.join(dir, "missing.jsonl")) == 0
    end

    test "returns the correct count after writes", %{tmp_dir: dir} do
      path = Path.join(dir, "out.jsonl")
      Enum.each(1..4, fn i -> Output.write(path, sample_candidate("id-#{i}")) end)
      assert Output.count(path) == 4
    end
  end

  describe "existing_ids/1" do
    test "returns a MapSet of all written ids", %{tmp_dir: dir} do
      path = Path.join(dir, "out.jsonl")
      Output.write(path, sample_candidate("abc"))
      Output.write(path, sample_candidate("def"))

      ids = Output.existing_ids(path)
      assert MapSet.member?(ids, "abc")
      assert MapSet.member?(ids, "def")
      assert MapSet.size(ids) == 2
    end

    test "returns empty MapSet for missing file", %{tmp_dir: dir} do
      assert MapSet.new() == Output.existing_ids(Path.join(dir, "missing.jsonl"))
    end
  end

  defp sample_candidate(id) do
    %{
      messages: [%{role: "user", content: "q"}, %{role: "assistant", content: "a"}],
      meta: %{id: id, domain: "elixir", task_type: "implement"}
    }
  end
end
