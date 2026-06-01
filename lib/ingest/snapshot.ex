defmodule Ingest.Snapshot do
  @moduledoc """
  Frozen, versioned dataset snapshots stored as JSONL splits.

  A snapshot directory contains:
    train.jsonl        - training records
    validation.jsonl   - held-out for epoch selection
    test.jsonl         - domain benchmark (never seen during training)
    regression.jsonl   - general capability checks
    snapshot.json      - metadata + hashes for lineage tracking

  Snapshots are write-once. Training consumes a snapshot by path;
  the pipeline must never point at mutable working files.
  """

  @splits [:train, :validation, :test, :regression]

  @type training_record :: %{
          required(:messages) => [%{role: String.t(), content: String.t()}],
          required(:meta) => map()
        }

  @type metadata :: %{
          dataset_id: String.t(),
          domain: String.t(),
          created_at: String.t(),
          base_model_candidate: String.t() | nil,
          tokenizer_id: String.t() | nil,
          split_counts: %{atom() => non_neg_integer()},
          split_hashes: %{atom() => String.t()},
          source_manifest_hash: String.t() | nil,
          brief_manifest_hash: String.t() | nil,
          generation_config_hash: String.t() | nil
        }

  @doc "Write records for one split to the snapshot directory."
  @spec write(Path.t(), atom(), Enumerable.t(training_record())) :: :ok
  def write(snapshot_dir, split, records) when split in @splits do
    File.mkdir_p!(snapshot_dir)
    path = split_path(snapshot_dir, split)

    File.open!(path, [:write, :utf8], fn file ->
      Enum.each(records, fn record ->
        IO.write(file, Jason.encode!(record) <> "\n")
      end)
    end)
  end

  @doc "Stream records from a split. Returns an Elixir stream."
  @spec read(Path.t(), atom()) :: Enumerable.t(training_record())
  def read(snapshot_dir, split) when split in @splits do
    split_path(snapshot_dir, split)
    |> File.stream!(:line)
    |> Stream.map(&Jason.decode!(&1, keys: :atoms))
  end

  @doc "Count the records in a split without loading all into memory."
  @spec count(Path.t(), atom()) :: non_neg_integer()
  def count(snapshot_dir, split) when split in @splits do
    path = split_path(snapshot_dir, split)

    if File.exists?(path) do
      path |> File.stream!(:line) |> Enum.count()
    else
      0
    end
  end

  @doc "SHA-256 hex digest of a file."
  @spec hash_file(Path.t()) :: String.t()
  def hash_file(path) do
    path
    |> File.stream!(2048)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  @doc "Write the snapshot metadata file."
  @spec write_metadata(Path.t(), map()) :: :ok
  def write_metadata(snapshot_dir, meta) do
    path = Path.join(snapshot_dir, "snapshot.json")
    File.write!(path, Jason.encode!(meta, pretty: true))
  end

  @doc "Read the snapshot metadata file."
  @spec read_metadata(Path.t()) :: {:ok, map()} | {:error, :not_found}
  def read_metadata(snapshot_dir) do
    path = Path.join(snapshot_dir, "snapshot.json")

    case File.read(path) do
      {:ok, contents} -> {:ok, Jason.decode!(contents)}
      {:error, :enoent} -> {:error, :not_found}
    end
  end

  @doc """
  Verify that a snapshot directory is complete and checksums match.
  A snapshot is valid if it has snapshot.json and at least a train split.
  """
  @spec verify(Path.t()) :: :ok | {:error, term()}
  def verify(snapshot_dir) do
    cond do
      not File.dir?(snapshot_dir) ->
        {:error, {:not_a_directory, snapshot_dir}}

      not File.exists?(Path.join(snapshot_dir, "snapshot.json")) ->
        {:error, :missing_metadata}

      not File.exists?(split_path(snapshot_dir, :train)) ->
        {:error, :missing_train_split}

      true ->
        :ok
    end
  end

  @doc "Build and write a complete snapshot from a map of split → records."
  @spec freeze(Path.t(), map(), map()) :: {:ok, metadata()} | {:error, term()}
  def freeze(snapshot_dir, splits, meta_fields) do
    File.mkdir_p!(snapshot_dir)

    split_counts =
      Map.new(splits, fn {split, records} ->
        write(snapshot_dir, split, records)
        {split, Enum.count(records)}
      end)

    split_hashes =
      Map.new(@splits, fn split ->
        path = split_path(snapshot_dir, split)
        hash = if File.exists?(path), do: hash_file(path), else: nil
        {split, hash}
      end)

    meta =
      Map.merge(meta_fields, %{
        split_counts: split_counts,
        split_hashes: split_hashes
      })

    write_metadata(snapshot_dir, meta)
    {:ok, meta}
  end

  defp split_path(dir, split), do: Path.join(dir, "#{split}.jsonl")
end
