defmodule Ingest.SnapshotTest do
  use ExUnit.Case, async: true

  alias Ingest.Snapshot

  @tag :tmp_dir
  test "write and read a split round-trips records", %{tmp_dir: dir} do
    records = [
      %{
        messages: [%{role: "user", content: "hello"}, %{role: "assistant", content: "hi"}],
        meta: %{id: "001"}
      },
      %{
        messages: [%{role: "user", content: "world"}, %{role: "assistant", content: "!"}],
        meta: %{id: "002"}
      }
    ]

    Snapshot.write(dir, :train, records)

    read_back = dir |> Snapshot.read(:train) |> Enum.to_list()
    assert length(read_back) == 2
    assert hd(read_back).meta.id == "001"
  end

  @tag :tmp_dir
  test "count/2 returns correct record count", %{tmp_dir: dir} do
    records = for i <- 1..5, do: %{messages: [], meta: %{id: "#{i}"}}
    Snapshot.write(dir, :train, records)
    assert Snapshot.count(dir, :train) == 5
  end

  @tag :tmp_dir
  test "count/2 returns 0 for missing split", %{tmp_dir: dir} do
    assert Snapshot.count(dir, :test) == 0
  end

  @tag :tmp_dir
  test "hash_file/1 is deterministic", %{tmp_dir: dir} do
    records = [%{messages: [], meta: %{id: "x"}}]
    Snapshot.write(dir, :train, records)
    path = Path.join(dir, "train.jsonl")
    assert Snapshot.hash_file(path) == Snapshot.hash_file(path)
  end

  @tag :tmp_dir
  test "hash_file/1 differs for different content", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "a.jsonl"), ~s({"a":1}\n))
    File.write!(Path.join(dir, "b.jsonl"), ~s({"b":2}\n))

    assert Snapshot.hash_file(Path.join(dir, "a.jsonl")) !=
             Snapshot.hash_file(Path.join(dir, "b.jsonl"))
  end

  @tag :tmp_dir
  test "write_metadata and read_metadata round-trip", %{tmp_dir: dir} do
    meta = %{dataset_id: "elixir-v0.1", domain: "elixir", train_count: 100}
    Snapshot.write_metadata(dir, meta)
    assert {:ok, read_back} = Snapshot.read_metadata(dir)
    assert read_back["dataset_id"] == "elixir-v0.1"
  end

  @tag :tmp_dir
  test "read_metadata returns :not_found for missing file", %{tmp_dir: dir} do
    assert {:error, :not_found} = Snapshot.read_metadata(dir)
  end

  @tag :tmp_dir
  test "verify/1 passes for a complete snapshot", %{tmp_dir: dir} do
    Snapshot.write(dir, :train, [%{messages: [], meta: %{id: "1"}}])
    Snapshot.write_metadata(dir, %{dataset_id: "test"})
    assert :ok = Snapshot.verify(dir)
  end

  @tag :tmp_dir
  test "verify/1 fails when train split is missing", %{tmp_dir: dir} do
    Snapshot.write_metadata(dir, %{dataset_id: "test"})
    assert {:error, :missing_train_split} = Snapshot.verify(dir)
  end

  test "verify/1 fails for non-existent directory" do
    assert {:error, {:not_a_directory, _}} = Snapshot.verify("/nonexistent/path")
  end

  @tag :tmp_dir
  test "freeze/3 writes all splits and metadata", %{tmp_dir: dir} do
    records = [%{messages: [], meta: %{id: "1"}}]

    {:ok, meta} =
      Snapshot.freeze(
        dir,
        %{train: records, test: records},
        %{dataset_id: "elixir-v0.1", domain: "elixir"}
      )

    assert meta.split_counts.train == 1
    assert meta.split_counts.test == 1
    assert is_binary(meta.split_hashes.train)
    assert :ok = Snapshot.verify(dir)
  end
end
