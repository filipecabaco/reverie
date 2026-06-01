defmodule DatasetGen.CheckpointTest do
  use ExUnit.Case, async: true

  alias DatasetGen.Checkpoint

  @moduletag :tmp_dir

  describe "load/1" do
    test "returns default state when file does not exist", %{tmp_dir: dir} do
      {:ok, state} = Checkpoint.load(Path.join(dir, "missing.json"))
      assert state["seen_ids"] == []
      assert state["kept"] == 0
      assert state["discarded"] == 0
    end

    test "loads a previously saved checkpoint", %{tmp_dir: dir} do
      path = Path.join(dir, "ckpt.json")
      state = %{"seen_ids" => ["id-1", "id-2"], "kept" => 2, "discarded" => 1, "saved_at" => nil}
      Checkpoint.save(path, state)

      {:ok, loaded} = Checkpoint.load(path)
      assert loaded["kept"] == 2
      assert "id-1" in loaded["seen_ids"]
    end

    test "returns error for invalid JSON", %{tmp_dir: dir} do
      path = Path.join(dir, "corrupt.json")
      File.write!(path, "not valid json")
      assert {:error, {:invalid_checkpoint, _}} = Checkpoint.load(path)
    end
  end

  describe "save/2" do
    test "writes checkpoint and stamps saved_at", %{tmp_dir: dir} do
      path = Path.join(dir, "ckpt.json")
      state = %{"seen_ids" => ["id-1"], "kept" => 1, "discarded" => 0, "saved_at" => nil}
      :ok = Checkpoint.save(path, state)

      {:ok, loaded} = Checkpoint.load(path)
      assert is_binary(loaded["saved_at"])
      assert {:ok, _, _} = DateTime.from_iso8601(loaded["saved_at"])
    end

    test "creates parent directories automatically", %{tmp_dir: dir} do
      path = Path.join([dir, "deep", "ckpt.json"])

      :ok =
        Checkpoint.save(path, %{
          "seen_ids" => [],
          "kept" => 0,
          "discarded" => 0,
          "saved_at" => nil
        })

      assert File.exists?(path)
    end
  end

  describe "mark_seen/3" do
    test "adds id to seen_ids and increments kept counter" do
      state = %{"seen_ids" => [], "kept" => 0, "discarded" => 0, "saved_at" => nil}
      updated = Checkpoint.mark_seen(state, "abc", :keep)
      assert "abc" in updated["seen_ids"]
      assert updated["kept"] == 1
      assert updated["discarded"] == 0
    end

    test "adds id to seen_ids and increments discarded counter" do
      state = %{"seen_ids" => [], "kept" => 0, "discarded" => 0, "saved_at" => nil}
      updated = Checkpoint.mark_seen(state, "xyz", :discard)
      assert "xyz" in updated["seen_ids"]
      assert updated["discarded"] == 1
      assert updated["kept"] == 0
    end

    test "accumulates multiple ids" do
      state = %{"seen_ids" => [], "kept" => 0, "discarded" => 0, "saved_at" => nil}

      final =
        state
        |> Checkpoint.mark_seen("id-1", :keep)
        |> Checkpoint.mark_seen("id-2", :keep)
        |> Checkpoint.mark_seen("id-3", :discard)

      assert length(final["seen_ids"]) == 3
      assert final["kept"] == 2
      assert final["discarded"] == 1
    end
  end

  describe "seen?/2 and seen_ids/1" do
    test "seen? returns true for a marked id" do
      state = %{"seen_ids" => ["id-1"], "kept" => 1, "discarded" => 0, "saved_at" => nil}
      assert Checkpoint.seen?(state, "id-1")
    end

    test "seen? returns false for an unknown id" do
      state = %{"seen_ids" => ["id-1"], "kept" => 1, "discarded" => 0, "saved_at" => nil}
      refute Checkpoint.seen?(state, "id-2")
    end

    test "seen_ids returns a MapSet" do
      state = %{"seen_ids" => ["a", "b"], "kept" => 2, "discarded" => 0, "saved_at" => nil}
      ids = Checkpoint.seen_ids(state)
      assert MapSet.member?(ids, "a")
      assert MapSet.member?(ids, "b")
    end
  end

  describe "summary/1" do
    test "returns a human-readable string" do
      state = %{"seen_ids" => ["x", "y"], "kept" => 1, "discarded" => 1, "saved_at" => nil}
      summary = Checkpoint.summary(state)
      assert String.contains?(summary, "kept=1")
      assert String.contains?(summary, "discarded=1")
    end
  end
end
