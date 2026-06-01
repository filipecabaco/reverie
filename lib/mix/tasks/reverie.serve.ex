defmodule Mix.Tasks.Reverie.Serve do
  use Mix.Task

  @shortdoc "Serve a trained domain adapter via mlx_lm"

  @moduledoc """
  Starts an OpenAI-compatible HTTP server for a fine-tuned LoRA adapter.

  Automatically picks the latest artifact version for the domain unless
  --dataset is given. Reads the base model from the adapter's config.json
  so you don't need to remember which model was used at training time.

  ## Usage

      mix reverie.serve --domain supabase
      mix reverie.serve --domain supabase --dataset v0.1 --port 8080

  ## Options

      --domain    Domain key. Required.
      --dataset   Artifact version. Defaults to the latest under data/<domain>/artifacts/.
      --port      Port to listen on. Default: 8080.
      --data-dir  Root data directory. Default: data.

  ## Calling the server

  Use the model name from adapter_config.json (printed at startup). Example:

      curl http://localhost:8080/v1/chat/completions \\
        -H "Content-Type: application/json" \\
        -d '{"model":"mlx-community/Qwen2.5-Coder-7B-Instruct-4bit","messages":[{"role":"user","content":"How do I enable RLS?"}]}'
  """

  @switches [
    domain: :string,
    dataset: :string,
    port: :integer,
    data_dir: :string
  ]

  @defaults [
    port: 8080,
    data_dir: "data"
  ]

  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    opts = Keyword.merge(@defaults, opts)

    domain = opts[:domain] || Mix.raise("--domain is required")
    data_dir = opts[:data_dir]
    port = opts[:port]

    artifacts_root = Path.join([data_dir, domain, "artifacts"])

    dataset = opts[:dataset] || latest_version!(artifacts_root, domain)
    adapter_path = Path.join([artifacts_root, dataset, "adapters"])

    unless File.dir?(adapter_path) do
      Mix.raise(
        "No adapter found at #{adapter_path}\nRun mix reverie.train --domain #{domain} first."
      )
    end

    config = read_adapter_config!(adapter_path)
    model = config["model"] || Mix.raise("adapter_config.json missing 'model' key")

    ensure_mlx_lm!()

    Mix.shell().info("Serving :#{domain} adapter")
    Mix.shell().info("   Version : #{dataset}")
    Mix.shell().info("   Model   : #{model}")
    Mix.shell().info("   Adapter : #{adapter_path}")
    Mix.shell().info("   Port    : #{port}\n")
    Mix.shell().info("Ready at http://localhost:#{port}/v1/chat/completions\n")

    Mix.shell().info("Example request:")
    Mix.shell().info(~s|  curl http://localhost:#{port}/v1/chat/completions \\|)
    Mix.shell().info(~s|    -H "Content-Type: application/json" \\|)

    Mix.shell().info(
      ~s|    -d '{"model":"#{model}","messages":[{"role":"user","content":"How do I enable RLS?"}]}'\n|
    )

    kill_port!(port)

    System.cmd(
      "python3",
      [
        "-m",
        "mlx_lm",
        "server",
        "--model",
        model,
        "--adapter-path",
        adapter_path,
        "--port",
        "#{port}"
      ],
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    )
  end

  defp latest_version!(artifacts_root, domain) do
    unless File.dir?(artifacts_root) do
      Mix.raise(
        "No artifacts found for domain #{domain} under #{artifacts_root}\nRun mix reverie.train first."
      )
    end

    case artifacts_root |> File.ls!() |> Enum.sort() |> List.last() do
      nil -> Mix.raise("No artifact versions found under #{artifacts_root}")
      version -> version
    end
  end

  defp read_adapter_config!(adapter_path) do
    config_path = Path.join(adapter_path, "adapter_config.json")

    unless File.exists?(config_path) do
      Mix.raise("adapter_config.json not found at #{config_path}")
    end

    config_path |> File.read!() |> JSON.decode!()
  end

  defp kill_port!(port) do
    case System.cmd("lsof", ["-ti", "tcp:#{port}"], stderr_to_stdout: true) do
      {"", _} ->
        :ok

      {pids, 0} ->
        pids
        |> String.split("\n", trim: true)
        |> Enum.each(fn pid ->
          Mix.shell().info("Killing existing process #{String.trim(pid)} on port #{port}")
          System.cmd("kill", ["-9", String.trim(pid)])
        end)

        Process.sleep(500)
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
end
