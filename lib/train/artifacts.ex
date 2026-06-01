defmodule Train.Artifacts do
  @moduledoc """
  Adapter artifact verification and metadata packaging.

  An artifact directory produced by the Python training script must contain
  at minimum: adapter_config.json, adapter_model.safetensors, checksums.json.
  The full package also includes provenance metadata written by Train.Job.
  """

  @required_files ~w(adapter_config.json adapter_model.safetensors checksums.json)

  @doc """
  Verify that an adapter directory contains all required files.
  Returns :ok or {:error, {:missing_files, [filename]}}.
  """
  @spec verify(Path.t()) :: :ok | {:error, term()}
  def verify(path) do
    cond do
      not File.dir?(path) ->
        {:error, {:not_a_directory, path}}

      true ->
        missing =
          @required_files
          |> Enum.reject(&File.exists?(Path.join(path, &1)))

        case missing do
          [] -> :ok
          _ -> {:error, {:missing_files, missing}}
        end
    end
  end

  @doc "Compute SHA-256 hex digest for every file in the artifact directory."
  @spec checksums(Path.t()) :: %{String.t() => String.t()}
  def checksums(path) do
    path
    |> File.ls!()
    |> Enum.sort()
    |> Map.new(fn filename ->
      digest =
        Path.join(path, filename)
        |> File.stream!(2048)
        |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
        |> :crypto.hash_final()
        |> Base.encode16(case: :lower)

      {filename, digest}
    end)
  end

  @doc """
  Write training_config.json into the artifact directory.
  Records the full provenance needed to reproduce this adapter.
  """
  @spec write_provenance(Path.t(), Train.Config.t(), map()) :: :ok
  def write_provenance(artifact_path, %Train.Config{} = config, extra \\ %{}) do
    provenance =
      Map.merge(
        %{
          base_model: config.base_model,
          dataset_path: config.dataset_path,
          seed: config.seed,
          lora_rank: config.lora_rank,
          lora_alpha: config.lora_alpha,
          lora_dropout: config.lora_dropout,
          target_modules: config.target_modules,
          num_epochs: config.num_epochs,
          per_device_batch_size: config.per_device_batch_size,
          learning_rate: config.learning_rate,
          max_seq_length: config.max_seq_length,
          quantization: config.quantization,
          double_quant: config.double_quant,
          compute_dtype: config.compute_dtype
        },
        extra
      )

    path = Path.join(artifact_path, "training_config.json")
    File.write!(path, Jason.encode!(provenance, pretty: true))
  end
end
