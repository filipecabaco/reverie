defmodule DatasetGen.Output do
  @moduledoc """
  JSONL output for generated training candidates.

  Files grow by appending. Reads stream line-by-line so large files
  don't have to be loaded into memory at once.
  """

  @doc "Append one candidate to the output file. Creates the file if absent."
  @spec write(Path.t(), map()) :: :ok
  def write(path, candidate) do
    File.mkdir_p!(Path.dirname(path))

    File.open!(path, [:append, :utf8], fn file ->
      IO.write(file, Jason.encode!(candidate) <> "\n")
    end)
  end

  @doc "Append a batch of candidates. Acquires the file handle once for the batch."
  @spec write_batch(Path.t(), [map()]) :: :ok
  def write_batch(path, candidates) when is_list(candidates) do
    File.mkdir_p!(Path.dirname(path))

    File.open!(path, [:append, :utf8], fn file ->
      Enum.each(candidates, fn candidate ->
        IO.write(file, Jason.encode!(candidate) <> "\n")
      end)
    end)
  end

  @doc "Stream candidates from an output file. Returns an empty stream if absent."
  @spec read_all(Path.t()) :: Enumerable.t(map())
  def read_all(path) do
    if File.exists?(path) do
      path
      |> File.stream!(:line)
      |> Stream.map(&Jason.decode!/1)
    else
      []
    end
  end

  @doc "Count candidates in an output file without loading all into memory."
  @spec count(Path.t()) :: non_neg_integer()
  def count(path) do
    if File.exists?(path), do: path |> File.stream!(:line) |> Enum.count(), else: 0
  end

  @doc "Collect all candidate IDs already written to a file."
  @spec existing_ids(Path.t()) :: MapSet.t(String.t())
  def existing_ids(path) do
    path
    |> read_all()
    |> Enum.map(& &1["meta"]["id"])
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end
end
