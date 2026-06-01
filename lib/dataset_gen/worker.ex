defmodule DatasetGen.Worker do
  @moduledoc """
  Full single-candidate validation pipeline (§8.4, §9).

  Pipeline:
    spec
    → fetch brief (Coordinator)
    → teacher.generate
    → Parser.parse
    → static_policy_gate
    → sandbox validate (or repair once if cfg.max_repairs > 0)
    → evidence_gate (Research.Agent.verify_candidate)
    → judge_gate (optional)
    → record

  Returns `{:keep, candidate}` or `{:discard, reason}`.

  The sandbox module is injectable via `opts[:sandbox]` so tests can stub it
  without touching the file system or Docker.
  """

  alias DatasetGen.{Config, Parser, TaskSpec}
  alias Research.{Agent, Coordinator}

  @type result :: {:keep, map()} | {:discard, term()}

  @spec process(TaskSpec.t(), Config.t(), keyword()) :: result()
  def process(%TaskSpec{} = spec, %Config{} = cfg, opts \\ []) do
    conn = opts[:conn]

    with {:ok, brief} <- fetch_brief(spec, cfg, conn),
         {:ok, raw} <- cfg.teacher.generate(spec, brief, opts),
         {:ok, parsed} <- Parser.parse(raw),
         :ok <- static_policy_gate(parsed),
         {:ok, validation} <- validate_or_repair(parsed, brief, cfg, opts),
         :ok <- evidence_gate(parsed, brief),
         :ok <- judge_gate(parsed, cfg) do
      {:keep, record(spec, parsed, validation, brief, cfg)}
    else
      {:error, reason} -> {:discard, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Brief
  # ---------------------------------------------------------------------------

  defp fetch_brief(_spec, %Config{brief_policy: :none}, _conn), do: {:ok, nil}

  defp fetch_brief(_spec, _cfg, nil), do: {:ok, nil}

  defp fetch_brief(spec, cfg, conn) do
    case Coordinator.verified_brief_for(spec.topic, cfg.brief_policy,
           conn: conn,
           domain: spec.domain
         ) do
      {:ok, brief} -> {:ok, brief}
      {:error, :not_found} -> {:ok, nil}
      error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Static policy gate
  # ---------------------------------------------------------------------------

  defp static_policy_gate(%{instruction: instruction, answer: answer}) do
    cond do
      String.length(instruction) < 10 ->
        {:error, :instruction_too_short}

      String.length(answer) < 20 ->
        {:error, :answer_too_short}

      true ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Sandbox validation + repair
  # ---------------------------------------------------------------------------

  defp validate_or_repair(parsed, brief, cfg, opts) do
    case run_sandbox(parsed, opts) do
      {:ok, %{compiled: true, tests_passed: passed} = v} when passed in [true, nil] ->
        {:ok, v}

      {:ok, v} when cfg.max_repairs > 0 ->
        repair_candidate(parsed, v.output, brief, cfg, opts)

      {:ok, %{compiled: false, output: out}} ->
        {:error, {:compile_failed, out}}

      {:ok, %{tests_passed: false, output: out}} ->
        {:error, {:tests_failed, out}}

      {:error, :timeout} ->
        {:error, :sandbox_timeout}

      {:error, reason} ->
        {:error, {:sandbox_error, reason}}
    end
  end

  defp run_sandbox(%{code: nil}, _opts) do
    {:ok, %{compiled: true, tests_passed: nil, output: ""}}
  end

  defp run_sandbox(%{code: code, test_code: test_code}, opts) do
    sandbox = Keyword.get(opts, :sandbox, DatasetGen.Sandbox)
    sandbox.validate(code, test_code)
  end

  defp repair_candidate(parsed, error_output, _brief, cfg, opts) do
    with {:ok, repaired_raw} <- cfg.teacher.repair(parsed, error_output, opts),
         {:ok, repaired} <- Parser.parse(repaired_raw) do
      run_sandbox(repaired, opts)
    end
  end

  # ---------------------------------------------------------------------------
  # Evidence gate
  # ---------------------------------------------------------------------------

  defp evidence_gate(_parsed, nil), do: :ok

  defp evidence_gate(parsed, brief) do
    candidate = %{
      messages: [
        %{role: "user", content: parsed.instruction},
        %{role: "assistant", content: parsed.answer}
      ]
    }

    Agent.verify_candidate(candidate, brief)
  end

  # ---------------------------------------------------------------------------
  # Judge gate
  # ---------------------------------------------------------------------------

  defp judge_gate(_parsed, %Config{judge: nil}), do: :ok
  defp judge_gate(_parsed, %Config{}), do: :ok

  # ---------------------------------------------------------------------------
  # Record
  # ---------------------------------------------------------------------------

  defp record(spec, parsed, validation, brief, cfg) do
    id =
      :crypto.hash(:sha256, parsed.instruction <> "\n" <> parsed.answer)
      |> Base.encode16(case: :lower)

    messages = [
      %{role: "user", content: parsed.instruction},
      %{role: "assistant", content: parsed.answer}
    ]

    meta = %{
      id: id,
      domain: cfg.domain,
      topic: spec.topic,
      task_type: spec.task_type,
      difficulty: spec.difficulty,
      source_kind: "synthetic_grounded",
      brief_id: brief && brief.id,
      compiled: validation.compiled,
      tests_passed: validation.tests_passed,
      code: parsed.code,
      test_code: parsed.test_code,
      generator_model: teacher_model(cfg),
      generated_at: DateTime.to_iso8601(DateTime.utc_now())
    }

    %{messages: messages, meta: meta}
  end

  defp teacher_model(%Config{teacher: DatasetGen.Teacher.Claude}), do: "claude-haiku-4-5"
  defp teacher_model(%Config{teacher: mod}), do: inspect(mod)
end
