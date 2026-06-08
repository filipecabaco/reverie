defmodule Corpus.IndexerTest do
  use ExUnit.Case, async: true

  alias Corpus.{Indexer, Manifest, ManifestEntry, Store}

  @moduletag :tmp_dir

  defp write_entry(dir, ref, content) do
    raw_path = Path.join([dir, "elixir", "raw", "#{ref}.md"])
    File.mkdir_p!(Path.dirname(raw_path))
    File.write!(raw_path, content)

    entry = %ManifestEntry{
      id: ManifestEntry.generate_id(:elixir, :official_hex_docs, ref),
      domain: :elixir,
      source_kind: :official_hex_docs,
      reference: ref,
      local_path: raw_path,
      fetched_at: DateTime.utc_now()
    }

    manifest_dir = Path.join([dir, "elixir", "manifests"])
    Manifest.append(manifest_dir, entry)
    entry
  end

  defp long_content(n \\ 5) do
    Enum.map_join(1..n, "\n\n", fn i ->
      "## Section #{i}\n\n" <> String.duplicate("word ", 50)
    end)
  end

  describe "index_domain/2 — happy path" do
    test "indexes entries and returns correct counts", %{tmp_dir: dir} do
      write_entry(dir, "ref-a", long_content())
      write_entry(dir, "ref-b", long_content())

      {:ok, %{indexed: indexed, skipped: skipped, errors: errors}} =
        Indexer.index_domain(:elixir, data_dir: dir)

      assert indexed == 2
      assert skipped == 0
      assert errors == 0
    end

    test "chunks are retrievable via Store after indexing", %{tmp_dir: dir} do
      write_entry(dir, "ref-searchable", long_content())
      {:ok, _} = Indexer.index_domain(:elixir, data_dir: dir)

      {:ok, db} = Store.open(:elixir, dir)

      try do
        {:ok, results} = Store.search_fts(db, "word", domain: :elixir, limit: 10)
        assert length(results) >= 1
        assert hd(results).source_reference == "ref-searchable"
      after
        Store.close(db)
      end
    end
  end

  describe "index_domain/2 — skip logic" do
    test "already-indexed references are skipped on second run", %{tmp_dir: dir} do
      write_entry(dir, "ref-once", long_content())

      {:ok, %{indexed: 1}} = Indexer.index_domain(:elixir, data_dir: dir)
      {:ok, %{indexed: 0, skipped: 1}} = Indexer.index_domain(:elixir, data_dir: dir)
    end

    test "force: true re-indexes already-indexed references", %{tmp_dir: dir} do
      write_entry(dir, "ref-force", long_content())

      {:ok, %{indexed: 1}} = Indexer.index_domain(:elixir, data_dir: dir)
      {:ok, %{indexed: 1, skipped: 0}} = Indexer.index_domain(:elixir, data_dir: dir, force: true)
    end

    test "rejected entries are not indexed", %{tmp_dir: dir} do
      raw_path = Path.join([dir, "elixir", "raw", "ref-rejected.md"])
      File.mkdir_p!(Path.dirname(raw_path))
      File.write!(raw_path, long_content())

      entry = %ManifestEntry{
        id: ManifestEntry.generate_id(:elixir, :official_hex_docs, "ref-rejected"),
        domain: :elixir,
        source_kind: :official_hex_docs,
        reference: "ref-rejected",
        local_path: raw_path,
        fetched_at: DateTime.utc_now(),
        terms_review: :rejected
      }

      manifest_dir = Path.join([dir, "elixir", "manifests"])
      Manifest.append(manifest_dir, entry)

      {:ok, %{indexed: 0, skipped: 0, errors: 0}} = Indexer.index_domain(:elixir, data_dir: dir)
    end
  end

  describe "index_domain/2 — error handling" do
    test "missing local_path counts as an error", %{tmp_dir: dir} do
      entry = %ManifestEntry{
        id: ManifestEntry.generate_id(:elixir, :official_hex_docs, "ref-missing"),
        domain: :elixir,
        source_kind: :official_hex_docs,
        reference: "ref-missing",
        local_path: Path.join(dir, "does_not_exist.md"),
        fetched_at: DateTime.utc_now()
      }

      manifest_dir = Path.join([dir, "elixir", "manifests"])
      Manifest.append(manifest_dir, entry)

      {:ok, %{indexed: 0, errors: 1}} = Indexer.index_domain(:elixir, data_dir: dir)
    end

    test "entries with no local_path count as errors", %{tmp_dir: dir} do
      entry = %ManifestEntry{
        id: ManifestEntry.generate_id(:elixir, :official_hex_docs, "ref-no-path"),
        domain: :elixir,
        source_kind: :official_hex_docs,
        reference: "ref-no-path",
        fetched_at: DateTime.utc_now()
      }

      manifest_dir = Path.join([dir, "elixir", "manifests"])
      Manifest.append(manifest_dir, entry)

      {:ok, %{indexed: 0, errors: 1}} = Indexer.index_domain(:elixir, data_dir: dir)
    end

    test "one error does not prevent other entries from being indexed", %{tmp_dir: dir} do
      write_entry(dir, "ref-good", long_content())

      bad_entry = %ManifestEntry{
        id: ManifestEntry.generate_id(:elixir, :official_hex_docs, "ref-bad"),
        domain: :elixir,
        source_kind: :official_hex_docs,
        reference: "ref-bad",
        local_path: Path.join(dir, "missing.md"),
        fetched_at: DateTime.utc_now()
      }

      manifest_dir = Path.join([dir, "elixir", "manifests"])
      Manifest.append(manifest_dir, bad_entry)

      {:ok, %{indexed: 1, errors: 1}} = Indexer.index_domain(:elixir, data_dir: dir)
    end
  end
end
