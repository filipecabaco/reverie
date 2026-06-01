defmodule Train.Bakeoff do
  @moduledoc """
  Runs the benchmark against each model candidate and produces a comparison report.

  The `responder_factory` receives a `ModelCandidate` and must return a function
  `(prompt :: String.t() -> code :: String.t())`. This keeps the bake-off
  model-agnostic — any inference backend (local, API, vLLM) can be plugged in.

  Usage:

      factory = fn candidate ->
        fn prompt -> MyInference.call(candidate.id, prompt) end
      end

      report = Train.Bakeoff.run(:elixir, Train.ModelCandidate.shortlist(), factory)
      IO.puts(Train.Bakeoff.Report.summary(report))
  """

  alias Evaluate.Benchmark
  alias Train.Bakeoff.{Compatibility, Report}
  alias Train.ModelCandidate

  @type responder_factory :: (ModelCandidate.t() -> (String.t() -> String.t()))

  @doc """
  Run the benchmark for every candidate in `candidates` and return a report.

  Options:
    - `:domain`        — benchmark domain (default `:elixir`)
    - `:only_eligible` — skip ineligible candidates (default `true`)
    - `:concurrency`   — max candidates evaluated in parallel. Defaults to
      `Application.get_env(:reverie, :bakeoff_concurrency, 1)`.
  """
  @spec run([ModelCandidate.t()], responder_factory(), keyword()) :: Report.t()
  def run(candidates, responder_factory, opts \\ []) do
    domain = Keyword.get(opts, :domain, :elixir)
    only_eligible = Keyword.get(opts, :only_eligible, true)

    concurrency =
      Keyword.get(opts, :concurrency, Application.get_env(:reverie, :bakeoff_concurrency, 1))

    to_evaluate =
      if only_eligible,
        do: Enum.filter(candidates, &ModelCandidate.eligible?/1),
        else: candidates

    results =
      Reverie.TaskSupervisor
      |> Task.Supervisor.async_stream_nolink(
        to_evaluate,
        fn candidate ->
          :telemetry.execute([:reverie, :bakeoff, :candidate_start], %{}, %{
            candidate: candidate.id,
            domain: domain
          })

          responder = responder_factory.(candidate)
          benchmark_report = Benchmark.run(domain, responder)

          :telemetry.execute([:reverie, :bakeoff, :candidate_done], %{}, %{
            candidate: candidate.id,
            compile_rate: benchmark_report.compile_rate,
            test_pass_rate: benchmark_report.test_pass_rate
          })

          {candidate, benchmark_report}
        end,
        max_concurrency: concurrency,
        timeout: :infinity
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> raise "bakeoff candidate failed: #{inspect(reason)}"
      end)

    Report.build(domain, results)
  end

  @doc """
  Persist a bake-off report to disk as JSON.
  Also writes a `compatibility/` subdirectory placeholder for each candidate.
  """
  @spec save(Report.t(), Path.t()) :: :ok | {:error, term()}
  def save(%Report{} = report, output_dir) do
    File.mkdir_p!(output_dir)

    with {:ok, json} <- Report.to_json(report) do
      File.write!(Path.join(output_dir, "bakeoff_report.json"), json)

      Enum.each(report.scores, fn %{candidate: c} ->
        compat_dir = Path.join([output_dir, "compatibility", slug(c.id)])
        File.mkdir_p!(compat_dir)
        checklist = Compatibility.new()
        summary = Compatibility.summary(checklist, c)
        File.write!(Path.join(compat_dir, "checklist.txt"), summary)
      end)

      :ok
    end
  end

  @doc """
  Record the selected base model to `data/selected_model.json`.
  This is the single source of truth for which base model subsequent
  steps (dataset freeze, training, evaluation) must use.
  """
  @spec record_selection(ModelCandidate.t(), Path.t()) :: :ok
  def record_selection(%ModelCandidate{} = candidate, output_dir \\ "data") do
    File.mkdir_p!(output_dir)
    path = Path.join(output_dir, "selected_model.json")

    payload = %{
      id: candidate.id,
      name: candidate.name,
      params_b: candidate.params_b,
      license: candidate.license,
      chat_template: candidate.chat_template,
      peft_target_modules: candidate.peft_target_modules,
      estimated_vram_4bit_gb: candidate.estimated_vram_4bit_gb,
      selected_at: DateTime.to_iso8601(DateTime.utc_now())
    }

    File.write!(path, Jason.encode!(payload, pretty: true))
  end

  @doc "Load the previously recorded model selection, if present."
  @spec load_selection(Path.t()) :: {:ok, map()} | {:error, :not_found}
  def load_selection(output_dir \\ "data") do
    path = Path.join(output_dir, "selected_model.json")

    case File.read(path) do
      {:ok, contents} -> {:ok, Jason.decode!(contents)}
      {:error, :enoent} -> {:error, :not_found}
    end
  end

  defp slug(model_id), do: String.replace(model_id, ~r"[^a-zA-Z0-9]", "-")
end
