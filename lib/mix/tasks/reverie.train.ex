defmodule Mix.Tasks.Reverie.Train do
  use Mix.Task

  @shortdoc "Fine-tune a domain adapter"

  @moduledoc """
  Fine-tune a LoRA adapter from a frozen dataset snapshot.

  Automatically selects the training backend based on hardware:
    mlx   — Apple Silicon (M1/M2/M3/M4), uses mlx-lm. Default on arm64.
    cuda  — NVIDIA GPU, uses QLoRA via bitsandbytes + PEFT.
    cpu   — CPU-only smoke test (very slow, for pipeline validation only).

  ## Usage

      mix reverie.train --domain supabase --dataset v0.1
      mix reverie.train --domain elixir --dataset v0.1 --backend mlx --iters 500

  ## Options

      --domain    Domain key. Required.
      --dataset   Dataset version (matches a directory under data/<domain>/datasets/).
      --backend   mlx, cuda, or cpu. Auto-detected if omitted.
      --model     Base model (HuggingFace ID or mlx-community ID). Auto-selected per backend.
      --iters     Training iterations (mlx). Default: 1000
      --epochs    Training epochs (cuda). Default: 2
      --data-dir  Root data directory. Default: data
      --out       Adapter output directory. Default: data/<domain>/artifacts/<dataset>
  """

  @switches [
    domain: :string,
    dataset: :string,
    backend: :string,
    model: :string,
    iters: :integer,
    epochs: :integer,
    data_dir: :string,
    out: :string
  ]

  @defaults [
    data_dir: "data",
    iters: 1000,
    epochs: 2
  ]

  # Good default models per backend — prefer 7B 4-bit for memory efficiency
  @default_models %{
    "mlx" => "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
    "cuda" => "Qwen/Qwen2.5-Coder-7B-Instruct",
    "cpu" => "mlx-community/Llama-3.2-1B-Instruct-4bit"
  }

  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    opts = Keyword.merge(@defaults, opts)

    domain_str = opts[:domain] || Mix.raise("--domain is required")
    dataset = opts[:dataset] || Mix.raise("--dataset is required")
    data_dir = opts[:data_dir]

    Mix.Task.run("app.start")
    domain = Mix.Tasks.Reverie.Helpers.resolve_domain(domain_str)

    backend = opts[:backend] || detect_backend()
    model = opts[:model] || @default_models[backend]

    dataset_path = Path.join([data_dir, domain_str, "datasets", dataset])
    out = opts[:out] || Path.join([data_dir, domain_str, "artifacts", dataset])

    unless File.dir?(dataset_path) do
      Mix.raise("Dataset not found: #{dataset_path}\nRun mix reverie.freeze first.")
    end

    Mix.shell().info("🏋️  Training :#{domain} adapter")
    Mix.shell().info("   Backend : #{backend}")
    Mix.shell().info("   Model   : #{model}")
    Mix.shell().info("   Dataset : #{dataset_path}")
    Mix.shell().info("   Output  : #{out}\n")

    File.mkdir_p!(out)

    case backend do
      "mlx" -> train_mlx(model, dataset_path, out, opts)
      "cuda" -> train_cuda(model, dataset_path, out, opts)
      "cpu" -> train_mlx(model, dataset_path, out, Keyword.put(opts, :iters, 5))
      _ -> Mix.raise("Unknown backend: #{backend}. Valid: mlx, cuda, cpu")
    end
  end

  # ---------------------------------------------------------------------------
  # MLX backend (Apple Silicon)
  # ---------------------------------------------------------------------------

  defp train_mlx(model, dataset_path, out, opts) do
    ensure_mlx_lm!()

    config = %{
      base_model: model,
      dataset_path: dataset_path,
      output_path: out,
      iters: opts[:iters],
      batch_size: 4,
      lora_layers: 16,
      learning_rate: 1.0e-4,
      seed: 42
    }

    script = priv_path("python/train_mlx.py")

    Mix.shell().info("Starting MLX training (#{opts[:iters]} iterations)...")

    case System.cmd("python3", [script],
           env: [{"CONFIG_JSON", Jason.encode!(config)}],
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        adapter_dir = Path.join(out, "adapters")
        Mix.shell().info("\n✓ Training complete. Adapter saved to #{adapter_dir}")
        print_next_steps(adapter_dir)

      {_, code} ->
        Mix.raise("Training failed (exit #{code})")
    end
  end

  # ---------------------------------------------------------------------------
  # CUDA backend (NVIDIA GPU)
  # ---------------------------------------------------------------------------

  defp train_cuda(model, dataset_path, out, opts) do
    config = %{
      base_model: model,
      dataset_path: dataset_path,
      output_path: out,
      num_epochs: opts[:epochs],
      seed: 42,
      smoke: false
    }

    script = priv_path("python/train.py")
    pyproject = File.read!(priv_path("python/pyproject.toml"))
    Pythonx.uv_init(pyproject)

    Mix.shell().info("Starting CUDA QLoRA training...")

    case Pythonx.eval(File.read!(script), %{"CONFIG_JSON" => Jason.encode!(config)}) do
      {:ok, output} ->
        result = Jason.decode!(output)
        Mix.shell().info("\n✓ Training complete. Metrics: #{inspect(result["metrics"])}")
        print_next_steps(out)

      {:error, reason} ->
        Mix.raise("Training failed: #{inspect(reason)}")
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp detect_backend do
    case System.cmd("uname", ["-m"]) do
      {"arm64\n", 0} ->
        Mix.shell().info("🍎 Apple Silicon detected → using MLX backend")
        "mlx"

      _ ->
        if cuda_available?(), do: "cuda", else: "cpu"
    end
  end

  defp cuda_available? do
    case System.cmd("nvidia-smi", [], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp ensure_mlx_lm! do
    case System.cmd("python3", ["-c", "import mlx_lm"], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      _ ->
        Mix.shell().info("Installing mlx-lm...")

        case System.cmd("pip3", ["install", "mlx-lm"], into: IO.stream(:stdio, :line)) do
          {_, 0} -> :ok
          {_, code} -> Mix.raise("Failed to install mlx-lm (exit #{code})")
        end
    end
  end

  defp print_next_steps(adapter_dir) do
    Mix.shell().info("""

    Next steps:
      1. Run the benchmark to measure baseline vs adapter:
         mix reverie.benchmark --domain <domain> --backend cli

      2. Evaluate four-way metrics in IEx:
         iex -S mix
         result = Evaluate.FourWay.run(:domain, %{
           base: fn p -> ... end,
           base_retrieval: fn p -> ... end,
           adapter: fn p -> ... end,
           adapter_retrieval: fn p -> ... end
         })
         IO.puts(Evaluate.FourWay.Result.summary(result))

      Adapter location: #{adapter_dir}
    """)
  end

  defp priv_path(relative), do: Path.join(:code.priv_dir(:reverie), relative)
end
