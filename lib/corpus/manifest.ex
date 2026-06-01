defmodule Corpus.Manifest do
  @moduledoc """
  Read/write the raw corpus manifest (JSONL at `data/<domain>/manifests/raw.jsonl`).

  The manifest is append-only. Hash-based resumption: before fetching a source,
  call `exists?/2` to skip references already recorded.
  """

  alias Corpus.ManifestEntry

  @filename "raw.jsonl"

  @doc "Canonical path to the manifest file for a domain."
  @spec path(Path.t()) :: Path.t()
  def path(manifest_dir), do: Path.join(manifest_dir, @filename)

  @doc "Append a single entry to the manifest. Creates the file and directory if needed."
  @spec append(Path.t(), ManifestEntry.t()) :: :ok
  def append(manifest_dir, %ManifestEntry{} = entry) do
    File.mkdir_p!(manifest_dir)

    File.open!(path(manifest_dir), [:append, :utf8], fn file ->
      IO.write(file, Jason.encode!(ManifestEntry.to_map(entry)) <> "\n")
    end)
  end

  @doc "Stream all entries from the manifest. Returns an empty stream if file absent."
  @spec read_all(Path.t()) :: Enumerable.t(ManifestEntry.t())
  def read_all(manifest_dir) do
    file = path(manifest_dir)

    if File.exists?(file) do
      file
      |> File.stream!(:line)
      |> Stream.map(&Jason.decode!/1)
      |> Stream.map(&ManifestEntry.from_map/1)
    else
      []
    end
  end

  @doc "Returns true if a reference is already recorded in the manifest."
  @spec exists?(Path.t(), String.t()) :: boolean()
  def exists?(manifest_dir, reference) do
    manifest_dir
    |> read_all()
    |> Enum.any?(&(&1.reference == reference))
  end

  @doc "Find a single entry by reference. Returns nil if not found."
  @spec lookup(Path.t(), String.t()) :: ManifestEntry.t() | nil
  def lookup(manifest_dir, reference) do
    manifest_dir
    |> read_all()
    |> Enum.find(&(&1.reference == reference))
  end

  @doc "Load existing references into a MapSet for O(1) duplicate checks."
  @spec existing_references(Path.t()) :: MapSet.t(String.t())
  def existing_references(manifest_dir) do
    manifest_dir
    |> read_all()
    |> Enum.map(& &1.reference)
    |> MapSet.new()
  end

  @doc "Count entries in the manifest."
  @spec count(Path.t()) :: non_neg_integer()
  def count(manifest_dir) do
    manifest_dir |> read_all() |> Enum.count()
  end
end
