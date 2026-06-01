defmodule DatasetGen.Teacher.Claude do
  @moduledoc """
  Teacher implementation backed by the Anthropic Messages API.

  Calls `POST https://api.anthropic.com/v1/messages` via Req.
  The API key is read from the `ANTHROPIC_API_KEY` environment variable
  at call time (not compile time).

  Default model is `claude-haiku-4-5` for cost-efficient volume generation.
  Override with `opts[:model]` when quality matters more than cost.
  """

  @behaviour DatasetGen.Teacher

  alias DatasetGen.TaskSpec
  alias Research.Brief

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"
  @default_model "claude-haiku-4-5"
  @max_tokens 4096

  @system_prompt """
  You generate training data for an Elixir domain adapter.

  For each request you must output ONLY a valid JSON object — no markdown fences,
  no explanation outside the JSON. The schema is:

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
  - Do NOT reference deprecated APIs or patterns the evidence brief marks as prohibited.
  - Be concise in instruction; be complete and correct in answer.
  """

  @impl true
  def generate(%TaskSpec{} = spec, brief, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    user_message = build_user_message(spec, brief)

    call_api(model, user_message)
  end

  @impl true
  def repair(candidate, validation_error, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)

    repair_message = """
    The following candidate failed validation with this error:

      #{validation_error}

    Original candidate:
    #{Jason.encode!(candidate, pretty: true)}

    Fix the issue and return a corrected JSON object using the same schema.
    """

    call_api(model, repair_message)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp build_user_message(%TaskSpec{} = spec, brief) do
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
        "Topic: choose a specific, high-value topic for :#{spec.domain} #{spec.task_type} tasks — pick something a developer genuinely needs to know, not a toy example"
      end

    """
    Domain: #{spec.domain}
    Task type: #{spec.task_type}
    #{topic_line}
    Difficulty: #{spec.difficulty}
    #{brief_section}
    Generate a training example for this task.
    """
  end

  defp call_api(model, user_message) do
    api_key = System.get_env("ANTHROPIC_API_KEY") || ""

    body = %{
      model: model,
      max_tokens: @max_tokens,
      system: @system_prompt,
      messages: [%{role: "user", content: user_message}]
    }

    case Req.post(@api_url,
           json: body,
           headers: [
             {"x-api-key", api_key},
             {"anthropic-version", @api_version},
             {"content-type", "application/json"}
           ],
           receive_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        parse_json_response(text)

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp parse_json_response(text) do
    cleaned = text |> String.trim() |> strip_fences()

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
        {:error, {:invalid_response, "expected a JSON object, got: #{inspect(text)}"}}

      {:error, reason} ->
        {:error, {:json_parse_error, reason, text}}
    end
  end

  defp strip_fences(text) do
    text
    |> String.replace(~r/^```(?:json)?\n?/, "")
    |> String.replace(~r/\n?```$/, "")
    |> String.trim()
  end
end
