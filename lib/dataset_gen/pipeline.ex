defmodule DatasetGen.Pipeline do
  @moduledoc """
  Broadway pipeline that drives Worker.process at scale (§10).

  Concurrency model (§8.5):
    - Processor concurrency → `cfg.generation_concurrency` (teacher API rate)
    - Sandbox slots        → `cfg.sandbox_slots` via SandboxPool (container capacity)
    - Output writes        → single batcher process (serial, no interleaving)

  The sandbox pool is independent of processor count so a burst of API
  responses does not accidentally launch too many containers at once.

  Starting a pipeline:

      {:ok, _} = DatasetGen.Pipeline.start_link(
        cfg: cfg,
        name: MyPipeline,
        sandbox_pool: pool_pid,
        sandbox: DatasetGen.Sandbox  # injectable for tests
      )

      # Push a batch of specs
      DatasetGen.Pipeline.push(MyPipeline, specs)

  The pipeline emits telemetry events on every candidate:
    [:reverie, :pipeline, :candidate_start]
    [:reverie, :pipeline, :candidate_kept]
    [:reverie, :pipeline, :candidate_discarded]
  """

  use Broadway

  alias DatasetGen.{Output, SandboxPool, Worker}
  alias Broadway.Message

  @doc "Start the pipeline. Requires :cfg and :sandbox_pool in opts."
  def start_link(opts) do
    cfg = Keyword.fetch!(opts, :cfg)
    sandbox_pool = Keyword.fetch!(opts, :sandbox_pool)
    sandbox = Keyword.get(opts, :sandbox, DatasetGen.Sandbox)
    conn = opts[:conn]
    name = Keyword.get(opts, :name, __MODULE__)

    context = %{cfg: cfg, sandbox_pool: sandbox_pool, sandbox: sandbox, conn: conn}

    Broadway.start_link(__MODULE__,
      name: name,
      producer: [module: {Broadway.DummyProducer, []}, concurrency: 1],
      processors: [default: [concurrency: cfg.generation_concurrency]],
      batchers: [output: [concurrency: 1, batch_size: 50, batch_timeout: 5_000]],
      context: context
    )
  end

  @doc "Push a list of TaskSpecs into a running pipeline."
  @spec push(GenServer.server(), [DatasetGen.TaskSpec.t()]) :: :ok
  def push(name \\ __MODULE__, specs) do
    messages =
      Enum.map(specs, fn spec ->
        %Message{data: spec, acknowledger: Broadway.NoopAcknowledger.init()}
      end)

    Broadway.push_messages(name, messages)
  end

  # ---------------------------------------------------------------------------
  # Broadway callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def handle_message(_, %Message{data: spec} = message, context) do
    %{cfg: cfg, sandbox_pool: pool, sandbox: sandbox, conn: conn} = context

    :telemetry.execute([:reverie, :pipeline, :candidate_start], %{}, %{
      domain: cfg.domain,
      topic: spec.topic,
      task_type: spec.task_type
    })

    SandboxPool.acquire(pool)

    result =
      try do
        Worker.process(spec, cfg, sandbox: sandbox, conn: conn)
      after
        SandboxPool.release(pool)
      end

    case result do
      {:keep, candidate} ->
        :telemetry.execute([:reverie, :pipeline, :candidate_kept], %{}, %{
          domain: cfg.domain,
          id: candidate.meta.id
        })

        message
        |> Message.update_data(fn _ -> candidate end)
        |> Message.put_batcher(:output)

      {:discard, reason} ->
        :telemetry.execute([:reverie, :pipeline, :candidate_discarded], %{}, %{
          domain: cfg.domain,
          reason: reason
        })

        Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(:output, messages, _batch_info, %{cfg: cfg}) do
    candidates = Enum.map(messages, & &1.data)
    :ok = Output.write_batch(cfg.out_path, candidates)

    :telemetry.execute([:reverie, :pipeline, :batch_written], %{count: length(candidates)}, %{
      domain: cfg.domain
    })

    messages
  end

  @impl true
  def handle_failed(messages, _context) do
    messages
  end
end
