defmodule DatasetGen.Checkpoint do
  @moduledoc """
  Tracks pipeline progress so a run can resume after interruption.

  The checkpoint file stores:
    - `seen_ids`   — candidate IDs that have been emitted to the output file
    - `kept`       — count of {:keep, _} results
    - `discarded`  — count of {:discard, _} results
    - `saved_at`   — ISO8601 timestamp of last save

  Resume logic: when a pipeline starts, load the checkpoint and filter
  out any TaskSpec whose canonical ID is already in `seen_ids`.
  """

  @default_state %{"seen_ids" => [], "kept" => 0, "discarded" => 0, "saved_at" => nil}

  @type state :: %{
          String.t() => list() | non_neg_integer() | String.t() | nil
        }

  @doc "Load checkpoint from disk. Returns the default empty state if the file doesn't exist."
  @spec load(Path.t()) :: {:ok, state()} | {:error, term()}
  def load(path) do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, state} -> {:ok, Map.merge(@default_state, state)}
          {:error, reason} -> {:error, {:invalid_checkpoint, reason}}
        end

      {:error, :enoent} ->
        {:ok, @default_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Save the checkpoint to disk."
  @spec save(Path.t(), state()) :: :ok | {:error, term()}
  def save(path, state) do
    File.mkdir_p!(Path.dirname(path))
    updated = Map.put(state, "saved_at", DateTime.to_iso8601(DateTime.utc_now()))
    File.write(path, Jason.encode!(updated, pretty: true))
  end

  @doc "Mark a candidate ID as seen. Returns the updated state."
  @spec mark_seen(state(), String.t(), :keep | :discard) :: state()
  def mark_seen(state, id, :keep) do
    state
    |> Map.update!("seen_ids", &[id | &1])
    |> Map.update!("kept", &(&1 + 1))
  end

  def mark_seen(state, id, :discard) do
    state
    |> Map.update!("seen_ids", &[id | &1])
    |> Map.update!("discarded", &(&1 + 1))
  end

  @doc "Returns a MapSet of already-seen candidate IDs."
  @spec seen_ids(state()) :: MapSet.t(String.t())
  def seen_ids(%{"seen_ids" => ids}), do: MapSet.new(ids)

  @doc "True if the candidate ID was already processed in a prior run."
  @spec seen?(state(), String.t()) :: boolean()
  def seen?(%{"seen_ids" => ids}, id), do: id in ids

  @doc "Stats summary string."
  @spec summary(state()) :: String.t()
  def summary(state) do
    "kept=#{state["kept"]} discarded=#{state["discarded"]} seen=#{length(state["seen_ids"])}"
  end
end
