defmodule DatasetGen.Generator do
  @moduledoc """
  Single-candidate generation flow — no concurrency, no sandbox yet.

  Pipeline: spec → attach brief → teacher.generate → parser.parse → candidate map.

  Step 9 (single-candidate validation) wires in the sandbox and evidence checks.
  Step 10 (Broadway) adds concurrency, rate limiting, and checkpointing.
  """

  alias DatasetGen.{Config, Parser, TaskSpec}
  alias Research.Coordinator

  @type candidate :: %{
          messages: [map()],
          meta: map()
        }

  @doc """
  Generate one candidate from a task spec.

  Returns `{:ok, candidate}` or `{:error, reason}`.
  The candidate is NOT sandbox-validated at this stage.
  """
  @spec generate(TaskSpec.t(), Config.t(), keyword()) ::
          {:ok, candidate()} | {:error, term()}
  def generate(%TaskSpec{} = spec, %Config{} = cfg, opts \\ []) do
    with {:ok, brief} <- fetch_brief(spec, cfg, opts),
         {:ok, raw} <- cfg.teacher.generate(spec, brief, opts),
         {:ok, parsed} <- Parser.parse(raw) do
      {:ok, build_candidate(spec, parsed, brief, cfg)}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp fetch_brief(spec, cfg, opts) do
    case cfg.brief_policy do
      :none ->
        {:ok, nil}

      policy ->
        conn = opts[:conn]

        if is_nil(conn) do
          {:ok, nil}
        else
          case Coordinator.verified_brief_for(spec.topic, policy, conn: conn, domain: spec.domain) do
            {:ok, brief} -> {:ok, brief}
            {:error, :not_found} -> {:ok, nil}
            error -> error
          end
        end
    end
  end

  defp build_candidate(spec, parsed, brief, cfg) do
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
      brief_id: brief && brief.id,
      source_kind: "synthetic_grounded",
      code: parsed.code,
      test_code: parsed.test_code,
      compiled: nil,
      tests_passed: nil,
      generator_model: teacher_model(cfg),
      generated_at: DateTime.to_iso8601(DateTime.utc_now())
    }

    %{messages: messages, meta: meta}
  end

  defp teacher_model(cfg) do
    case cfg.teacher do
      DatasetGen.Teacher.Claude -> "claude-haiku-4-5"
      mod -> inspect(mod)
    end
  end
end
