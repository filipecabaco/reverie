defmodule Train.Job do
  @moduledoc """
  Orchestrates a QLoRA training run.

  The FLAME runner is injectable via the `:runner` option so tests can
  bypass remote execution entirely. Telemetry events are emitted at each
  phase boundary so the calling process can log progress without polling.

  Phases:
    1. Validate config + dataset snapshot
    2. On the configured runner, call Python (Pythonx) with the training script
    3. Verify produced artifacts
    4. Write provenance metadata
    5. Return artifact path + metrics

  The durable result is the adapter on disk (or S3, once upload is wired in §2.4).
  The FLAME runner is ephemeral — all outputs must be persisted before it exits.
  """

  alias Ingest.Snapshot
  alias Train.{Artifacts, Config}

  @python_script "priv/python/train.py"
  @python_project "priv/python/pyproject.toml"

  @type result :: %{
          adapter_path: Path.t(),
          metrics: map(),
          checksums: map()
        }

  @doc """
  Run multiple training jobs concurrently.

  Options:
    - `:concurrency` — max parallel jobs. Defaults to
      `Application.get_env(:reverie, :train_concurrency, 1)`.
    - All options from `run/2` are forwarded to each job.
  """
  @spec run_many([Config.t()], keyword()) :: [{:ok, result()} | {:error, term()}]
  def run_many(configs, opts \\ []) when is_list(configs) do
    concurrency =
      Keyword.get(opts, :concurrency, Application.get_env(:reverie, :train_concurrency, 1))

    Reverie.TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(
      configs,
      fn config -> run(config, opts) end,
      max_concurrency: concurrency,
      timeout: :infinity
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:task_exit, reason}}
    end)
  end

  @doc """
  Run a training job.

  Options:
    - `:runner` — `:local` (run in current process) or a FLAME pool name.
      Defaults to `Application.get_env(:reverie, :flame_runner, :local)`.
  """
  @spec run(Config.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def run(%Config{} = config, opts \\ []) do
    :telemetry.execute([:reverie, :train, :start], %{}, %{base_model: config.base_model})

    with :ok <- Config.validate(config),
         :ok <- Snapshot.verify(config.dataset_path) do
      runner = Keyword.get(opts, :runner, Application.get_env(:reverie, :flame_runner, :local))
      dispatch(config, runner)
    end
  end

  # ---------------------------------------------------------------------------
  # Runner dispatch
  # ---------------------------------------------------------------------------

  defp dispatch(config, :local) do
    invoke_python(config)
  end

  defp dispatch(config, runner) do
    FLAME.call(runner, fn -> invoke_python(config) end)
  end

  # ---------------------------------------------------------------------------
  # Python bridge
  # ---------------------------------------------------------------------------

  defp invoke_python(config) do
    :telemetry.execute([:reverie, :train, :python_start], %{}, %{})

    pyproject = File.read!(priv_path(@python_project))
    Pythonx.uv_init(pyproject)

    script = File.read!(priv_path(@python_script))
    config_json = Jason.encode!(Config.to_python_args(config))

    result = Pythonx.eval(script, %{"CONFIG_JSON" => config_json})

    :telemetry.execute([:reverie, :train, :python_done], %{}, %{})

    parse_result(result, config)
  end

  defp parse_result({:ok, output}, config) do
    with {:ok, decoded} <- Jason.decode(output),
         :ok <- Artifacts.verify(config.output_path) do
      Artifacts.write_provenance(config.output_path, config, %{
        dataset_hash: snapshot_hash(config.dataset_path)
      })

      checksums = Artifacts.checksums(config.output_path)

      :telemetry.execute([:reverie, :train, :done], %{}, %{
        adapter_path: config.output_path,
        metrics: decoded["metrics"]
      })

      {:ok,
       %{
         adapter_path: config.output_path,
         metrics: Map.get(decoded, "metrics", %{}),
         checksums: checksums
       }}
    end
  end

  defp parse_result({:error, reason}, _config) do
    :telemetry.execute([:reverie, :train, :error], %{}, %{reason: reason})
    {:error, {:python_error, reason}}
  end

  defp snapshot_hash(dataset_path) do
    snapshot_json = Path.join(dataset_path, "snapshot.json")
    if File.exists?(snapshot_json), do: Ingest.Snapshot.hash_file(snapshot_json), else: nil
  end

  defp priv_path(relative), do: Path.join(:code.priv_dir(:reverie), relative)
end
