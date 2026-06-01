defmodule DatasetGen.Teacher.ClaudeCLI do
  @moduledoc """
  Teacher implementation backed by the `claude` CLI.

  Uses `claude -p "<prompt>"` so generation works without API credits —
  the CLI reuses the session from `claude auth login`.

  Pass `--backend cli` to any Reverie Mix task to activate this teacher.
  """

  @behaviour DatasetGen.Teacher

  alias DatasetGen.TaskSpec
  alias Research.Brief

  @impl true
  def generate(%TaskSpec{} = spec, brief, _opts \\ []) do
    prompt = build_prompt(spec, brief)
    call_cli(prompt)
  end

  @impl true
  def repair(candidate, validation_error, _opts \\ []) do
    prompt = """
    #{system_prompt()}

    The following candidate failed validation with this error:

      #{validation_error}

    Original candidate:
    #{Jason.encode!(candidate, pretty: true)}

    Fix the issue and return a corrected JSON object using the same schema.
    """

    call_cli(prompt)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp build_prompt(%TaskSpec{} = spec, brief) do
    brief_section =
      case brief do
        nil ->
          ""

        %Brief{facts: facts, prohibited_patterns: prohibited} ->
          prohibited_text =
            case prohibited do
              nil ->
                ""

              [] ->
                ""

              patterns ->
                "\n\nDo NOT use or recommend:\n" <> Enum.map_join(patterns, "\n", &"- #{&1}")
            end

          facts_text = facts |> Enum.take(6) |> Enum.map_join("\n", &"- #{&1}")

          """

          Evidence (verified facts about #{spec.topic}):
          #{facts_text}#{prohibited_text}
          """
      end

    topic_line =
      if spec.topic do
        "Topic: #{spec.topic}"
      else
        "Topic: choose a specific, high-value topic for :#{spec.domain} #{spec.task_type} tasks"
      end

    """
    #{system_prompt()}

    Domain: #{spec.domain}
    Task type: #{spec.task_type}
    #{topic_line}
    Difficulty: #{spec.difficulty}
    #{brief_section}
    Generate a training example for this task.
    """
  end

  defp system_prompt do
    """
    You generate training data for an Elixir domain adapter.

    Output ONLY a valid JSON object — no markdown fences, no explanation outside the JSON:

      {
        "instruction": "<the user-facing question or task>",
        "answer": "<your complete response>",
        "code": "<Elixir source code if applicable, otherwise null>",
        "test_code": "<ExUnit test code if applicable, otherwise null>"
      }

    Rules:
    - instruction and answer are required and must be non-empty strings.
    - code must be valid Elixir if present (not null).
    - test_code may only be present when code is also present.
    - test_code must be a standalone ExUnit test module — do NOT call ExUnit.start().
    """
  end

  defp call_cli(prompt) do
    env = cli_env() ++ [{"REVERIE_PROMPT", prompt}]

    case System.cmd("sh", ["-c", "claude -p \"$REVERIE_PROMPT\" </dev/null 2>/dev/null"],
           env: env,
           stderr_to_stdout: false
         ) do
      {output, 0} ->
        parse_response(String.trim(output))

      {error, code} ->
        {:error, {:cli_error, code, error}}
    end
  end

  defp parse_response(text) do
    cleaned = text |> strip_fences() |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, map} when is_map(map) ->
        {:ok,
         %{
           instruction: map["instruction"],
           answer: map["answer"],
           code: map["code"],
           test_code: map["test_code"]
         }}

      {:ok, _} ->
        {:error, {:invalid_response, text}}

      {:error, _} ->
        {:error, {:json_parse_error, text}}
    end
  end

  # Unset ANTHROPIC_API_KEY so the CLI uses the OAuth session from
  # `claude auth login` rather than the API key (which may have no credits).
  defp cli_env do
    [{"ANTHROPIC_API_KEY", ""}, {"CLAUDE_API_KEY", ""}]
  end

  defp strip_fences(text) do
    text
    |> String.replace(~r/^```(?:json)?\n?/, "")
    |> String.replace(~r/\n?```$/, "")
    |> String.trim()
  end
end
