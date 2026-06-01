defmodule Corpus.ManifestTest do
  use ExUnit.Case, async: true

  alias Corpus.{Manifest, ManifestEntry}

  @moduletag :tmp_dir

  describe "append/2 and read_all/1" do
    test "appends entries and streams them back", %{tmp_dir: dir} do
      Manifest.append(dir, entry("ref-1"))
      Manifest.append(dir, entry("ref-2"))

      [e1, e2] = dir |> Manifest.read_all() |> Enum.to_list()
      assert e1.reference == "ref-1"
      assert e2.reference == "ref-2"
    end

    test "creates directory if missing", %{tmp_dir: dir} do
      nested = Path.join(dir, "deep/manifests")
      Manifest.append(nested, entry("ref-1"))
      assert File.exists?(Manifest.path(nested))
    end

    test "read_all returns empty stream for missing file", %{tmp_dir: dir} do
      assert [] = dir |> Manifest.read_all() |> Enum.to_list()
    end
  end

  describe "exists?/2" do
    test "returns true for an appended reference", %{tmp_dir: dir} do
      Manifest.append(dir, entry("https://hexdocs.pm/ecto"))
      assert Manifest.exists?(dir, "https://hexdocs.pm/ecto")
    end

    test "returns false for an unknown reference", %{tmp_dir: dir} do
      Manifest.append(dir, entry("https://hexdocs.pm/ecto"))
      refute Manifest.exists?(dir, "https://hexdocs.pm/phoenix")
    end

    test "returns false on empty manifest", %{tmp_dir: dir} do
      refute Manifest.exists?(dir, "anything")
    end
  end

  describe "lookup/2" do
    test "returns the matching entry", %{tmp_dir: dir} do
      Manifest.append(dir, entry("ref-a"))
      Manifest.append(dir, entry("ref-b"))

      assert %ManifestEntry{reference: "ref-b"} = Manifest.lookup(dir, "ref-b")
    end

    test "returns nil when not found", %{tmp_dir: dir} do
      assert Manifest.lookup(dir, "nope") == nil
    end
  end

  describe "existing_references/1" do
    test "returns a MapSet of all references", %{tmp_dir: dir} do
      Manifest.append(dir, entry("ref-1"))
      Manifest.append(dir, entry("ref-2"))

      refs = Manifest.existing_references(dir)
      assert MapSet.member?(refs, "ref-1")
      assert MapSet.member?(refs, "ref-2")
      assert MapSet.size(refs) == 2
    end

    test "returns empty MapSet for missing file", %{tmp_dir: dir} do
      assert MapSet.new() == Manifest.existing_references(dir)
    end
  end

  describe "count/1" do
    test "returns 0 for empty manifest", %{tmp_dir: dir} do
      assert Manifest.count(dir) == 0
    end

    test "counts appended entries", %{tmp_dir: dir} do
      Enum.each(1..3, fn i -> Manifest.append(dir, entry("ref-#{i}")) end)
      assert Manifest.count(dir) == 3
    end
  end

  defp entry(reference) do
    %ManifestEntry{
      id: ManifestEntry.generate_id(:elixir, :official_hex_docs, reference),
      domain: :elixir,
      source_kind: :official_hex_docs,
      reference: reference,
      fetched_at: DateTime.utc_now() |> DateTime.truncate(:second),
      terms_review: :pending_review,
      training_allowed: :unknown,
      redistribution_allowed: :unknown,
      contains_personal_data: :unknown
    }
  end
end
