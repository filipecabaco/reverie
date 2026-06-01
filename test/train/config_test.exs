defmodule Train.ConfigTest do
  use ExUnit.Case, async: true

  alias Train.Config

  @tag :tmp_dir
  test "validate/1 passes for a complete valid config", %{tmp_dir: dir} do
    config = valid_config(dir)
    assert :ok = Config.validate(config)
  end

  @tag :tmp_dir
  test "validate/1 fails when dataset_path does not exist", %{tmp_dir: _dir} do
    config = %Config{
      base_model: "facebook/opt-125m",
      dataset_path: "/nonexistent/path",
      output_path: "/tmp/out",
      seed: 42
    }

    assert {:error, errors} = Config.validate(config)
    assert Enum.any?(errors, &String.contains?(&1, "dataset_path"))
  end

  @tag :tmp_dir
  test "validate/1 collects all errors", %{tmp_dir: dir} do
    config = %Config{
      base_model: "",
      dataset_path: dir,
      output_path: "/tmp/out",
      seed: 42,
      lora_rank: 999,
      learning_rate: -1.0
    }

    assert {:error, errors} = Config.validate(config)
    assert length(errors) >= 3
  end

  @tag :tmp_dir
  test "to_python_args/1 serializes all fields to a plain map", %{tmp_dir: dir} do
    config = valid_config(dir)
    args = Config.to_python_args(config)

    assert args.base_model == config.base_model
    assert args.seed == config.seed
    assert args.lora_rank == config.lora_rank
    assert is_binary(args.quantization)
    assert is_binary(args.compute_dtype)
    assert is_boolean(args.smoke)
  end

  @tag :tmp_dir
  test "to_python_args/1 is JSON-encodable", %{tmp_dir: dir} do
    args = dir |> valid_config() |> Config.to_python_args()
    assert {:ok, _} = Jason.encode(args)
  end

  @tag :tmp_dir
  test "defaults match plan §10.1", %{tmp_dir: dir} do
    config = valid_config(dir)
    assert config.lora_rank == 16
    assert config.lora_alpha == 32
    assert config.lora_dropout == 0.05
    assert config.target_modules == "all-linear"
    assert config.num_epochs == 2
    assert config.quantization == :nf4
    assert config.double_quant == true
    assert config.compute_dtype == :bfloat16
    assert config.smoke == false
  end

  defp valid_config(dir) do
    %Config{
      base_model: "facebook/opt-125m",
      dataset_path: dir,
      output_path: Path.join(dir, "adapter"),
      seed: 42
    }
  end
end
