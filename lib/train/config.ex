defmodule Train.Config do
  @moduledoc """
  QLoRA training configuration.

  Defaults follow the plan's starting config (§10.1):
  rank 16, alpha 32, dropout 0.05, all-linear target modules,
  NF4 quant with double-quant, BF16 compute, 2 epochs.
  """

  @enforce_keys [:base_model, :dataset_path, :output_path, :seed]
  defstruct [
    :base_model,
    :dataset_path,
    :output_path,
    :seed,
    lora_rank: 16,
    lora_alpha: 32,
    lora_dropout: 0.05,
    target_modules: "all-linear",
    num_epochs: 2,
    per_device_batch_size: 4,
    learning_rate: 2.0e-4,
    max_seq_length: 2048,
    quantization: :nf4,
    double_quant: true,
    compute_dtype: :bfloat16,
    gradient_checkpointing: true,
    # smoke: true → 1-step CPU run, no quantization (seam test only)
    smoke: false
  ]

  @type t :: %__MODULE__{
          base_model: String.t(),
          dataset_path: Path.t(),
          output_path: Path.t(),
          seed: non_neg_integer(),
          lora_rank: pos_integer(),
          lora_alpha: pos_integer(),
          lora_dropout: float(),
          target_modules: String.t() | [String.t()],
          num_epochs: pos_integer(),
          per_device_batch_size: pos_integer(),
          learning_rate: float(),
          max_seq_length: pos_integer(),
          quantization: :nf4 | :fp4,
          double_quant: boolean(),
          compute_dtype: :bfloat16 | :float16,
          gradient_checkpointing: boolean(),
          smoke: boolean()
        }

  @doc "Validate configuration. Returns :ok or {:error, [reason]}."
  @spec validate(t()) :: :ok | {:error, [String.t()]}
  def validate(%__MODULE__{} = config) do
    errors =
      []
      |> check(config.base_model != nil and config.base_model != "", "base_model is required")
      |> check(config.seed >= 0, "seed must be a non-negative integer")
      |> check(config.lora_rank in [8, 16, 32, 64], "lora_rank must be 8, 16, 32, or 64")
      |> check(config.lora_alpha > 0, "lora_alpha must be positive")
      |> check(
        config.lora_dropout >= 0.0 and config.lora_dropout < 1.0,
        "lora_dropout must be in [0, 1)"
      )
      |> check(config.num_epochs >= 1, "num_epochs must be >= 1")
      |> check(config.learning_rate > 0.0, "learning_rate must be positive")
      |> check(config.max_seq_length >= 64, "max_seq_length must be >= 64")
      |> check(config.per_device_batch_size >= 1, "per_device_batch_size must be >= 1")
      |> check(
        File.exists?(config.dataset_path),
        "dataset_path does not exist: #{config.dataset_path}"
      )

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  @doc "Convert config to a plain map suitable for passing to Python via JSON."
  @spec to_python_args(t()) :: map()
  def to_python_args(%__MODULE__{} = config) do
    %{
      base_model: config.base_model,
      dataset_path: config.dataset_path,
      output_path: config.output_path,
      seed: config.seed,
      lora_rank: config.lora_rank,
      lora_alpha: config.lora_alpha,
      lora_dropout: config.lora_dropout,
      target_modules: config.target_modules,
      num_epochs: config.num_epochs,
      per_device_batch_size: config.per_device_batch_size,
      learning_rate: config.learning_rate,
      max_seq_length: config.max_seq_length,
      quantization: Atom.to_string(config.quantization),
      double_quant: config.double_quant,
      compute_dtype: Atom.to_string(config.compute_dtype),
      gradient_checkpointing: config.gradient_checkpointing,
      smoke: config.smoke
    }
  end

  defp check(errors, true, _msg), do: errors
  defp check(errors, false, msg), do: [msg | errors]
end
