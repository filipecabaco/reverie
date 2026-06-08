defmodule Corpus.Indexer do
  @moduledoc """
  Processes raw manifest entries into searchable corpus chunks.

  Reads a domain's manifest, filters to indexable entries (not explicitly
  rejected by source policy), chunks each document with `Corpus.Chunker`,
  and inserts the results into the corpus store. Already-indexed source
  references are skipped by default; pass `force: true` to re-index.

  Rights metadata (`training_allowed`, `redistribution_allowed`) from the
  manifest entry is stored in each chunk's metadata so downstream pipelines
  can apply per-chunk filtering without re-joining the manifest.
  """

  alias Corpus.{Chunker, ManifestEntry, Manifest, Store}

  @type result :: %{
          indexed: non_neg_integer(),
          skipped: non_neg_integer(),
          errors: non_neg_integer()
        }

  @doc """
  Index all unindexed manifest entries for `domain`.

  Options:
    - `:data_dir` — root data directory (default `"data"`)
    - `:force`    — re-index already-indexed references (default `false`)
  """
  @spec index_domain(atom(), keyword()) :: {:ok, result()} | {:error, term()}
  def index_domain(domain, opts \\ []) do
    data_dir = Keyword.get(opts, :data_dir, "data")
    force = Keyword.get(opts, :force, false)

    manifest_dir = Path.join([data_dir, to_string(domain), "manifests"])
    entries = manifest_dir |> Manifest.read_all() |> Enum.to_list()
    indexable = Enum.filter(entries, &indexable?/1)

    with {:ok, db} <- Store.open(domain, data_dir) do
      already_indexed =
        if force, do: MapSet.new(), else: Store.indexed_references(db, domain)

      results =
        Enum.map(indexable, fn entry ->
          if MapSet.member?(already_indexed, entry.reference) do
            {:skip, entry.reference}
          else
            index_entry(db, domain, entry)
          end
        end)

      Store.close(db)

      {:ok,
       %{
         indexed: Enum.count(results, &match?({:ok, _}, &1)),
         skipped: Enum.count(results, &match?({:skip, _}, &1)),
         errors: Enum.count(results, &match?({:error, _}, &1))
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp indexable?(%ManifestEntry{terms_review: :rejected}), do: false
  defp indexable?(_), do: true

  defp index_entry(db, domain, entry) do
    with {:ok, content} <- read_content(entry),
         chunks = Chunker.chunk(content, entry.reference),
         true <- chunks != [] do
      rights = %{
        training_allowed: entry.training_allowed,
        redistribution_allowed: entry.redistribution_allowed
      }

      Enum.each(chunks, fn chunk ->
        enriched_meta = Map.merge(chunk.metadata, rights)
        Store.insert_chunk(db, %{chunk | metadata: enriched_meta, domain: domain})
      end)

      {:ok, entry.reference}
    else
      false -> {:skip, entry.reference}
      {:error, reason} -> {:error, {entry.reference, reason}}
    end
  rescue
    e -> {:error, {entry.reference, Exception.message(e)}}
  end

  defp read_content(%ManifestEntry{local_path: path}) when is_binary(path), do: File.read(path)
  defp read_content(_), do: {:error, :no_local_path}
end
