defmodule Mix.Tasks.Reverie.Helpers do
  @domains_file "priv/domains.exs"

  @doc """
  Resolves a domain name string to its atom key by looking it up in
  priv/domains.exs. The atom comes from the file's data, not from
  string conversion.
  """
  def resolve_domain(name) do
    {entries, _} = Code.eval_file(@domains_file)

    case Enum.find(entries, &(to_string(&1.key) == name)) do
      nil ->
        known = entries |> Enum.map_join(", ", &to_string(&1.key))
        Mix.raise("Unknown domain: #{inspect(name)}. Known domains: #{known}")

      entry ->
        entry.key
    end
  end

  @doc "Load all domain entries from priv/domains.exs."
  def load_domains do
    {entries, _} = Code.eval_file(@domains_file)
    entries
  end

  @doc """
  Resolves --backend to a teacher module and a topic-suggestion function.

  Supported values:
    "api"  (default) — direct Anthropic API via Req; requires ANTHROPIC_API_KEY with credits
    "cli"            — shells out to `claude -p`; uses your existing Claude Code session
  """
  def resolve_backend(backend) do
    case backend do
      "cli" -> DatasetGen.Teacher.ClaudeCLI
      "api" -> DatasetGen.Teacher.Claude
      nil -> DatasetGen.Teacher.Claude
      other -> Mix.raise("Unknown --backend #{inspect(other)}. Valid: api, cli")
    end
  end

  @doc """
  Ask the teacher to suggest a topic for a domain.
  Uses the Claude CLI or API depending on the backend.
  """
  def suggest_topic(domain, backend) do
    prompt =
      "What is the single most important practical topic a developer needs to understand " <>
        "when working with #{domain}? Reply with the topic name only, 2-6 words, no punctuation."

    case backend do
      "cli" -> suggest_via_cli(prompt, domain)
      _ -> suggest_via_api(prompt)
    end
  end

  defp suggest_via_cli(prompt, _domain) do
    case run_claude(prompt) do
      {output, 0} ->
        topic = output |> String.trim() |> String.split("\n") |> List.last() |> String.trim()
        Mix.shell().info("🤖 Teacher suggests topic: #{topic}")
        topic

      {error, code} ->
        Mix.raise("CLI error (exit #{code}): #{error}\nPass --topic to skip this step.")
    end
  end

  defp suggest_via_api(prompt) do
    api_key = System.get_env("ANTHROPIC_API_KEY", "")

    body = %{
      model: "claude-haiku-4-5",
      max_tokens: 64,
      system: "Reply with ONLY a short topic name — no explanation, no punctuation.",
      messages: [%{role: "user", content: prompt}]
    }

    case Req.post("https://api.anthropic.com/v1/messages",
           json: body,
           headers: [{"x-api-key", api_key}, {"anthropic-version", "2023-06-01"}],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        topic = String.trim(text)
        Mix.shell().info("🤖 Teacher suggests topic: #{topic}")
        topic

      {:ok, %{status: 400, body: %{"error" => %{"message" => msg}}}} ->
        Mix.raise(
          "API error: #{msg}\n\nAdd credits at console.anthropic.com or use --backend cli"
        )

      {:ok, %{status: status, body: body}} ->
        Mix.raise("API returned #{status}: #{inspect(body)}\nTry --backend cli instead.")

      {:error, reason} ->
        Mix.raise("Request failed: #{inspect(reason)}\nTry --backend cli instead.")
    end
  end

  # Unset ANTHROPIC_API_KEY so the claude CLI uses the OAuth session
  # from `claude auth login` rather than the API key (which may have no credits).
  def cli_env do
    [{"ANTHROPIC_API_KEY", ""}, {"CLAUDE_API_KEY", ""}]
  end

  @doc """
  Run `claude -p` with stdin closed so the CLI doesn't wait for piped input.
  Passes the prompt via an env var to avoid shell quoting issues.
  Returns `{output, exit_code}`.
  """
  def run_claude(prompt) do
    env = cli_env() ++ [{"REVERIE_PROMPT", prompt}]

    System.cmd("sh", ["-c", "claude -p \"$REVERIE_PROMPT\" < /dev/null"],
      env: env,
      stderr_to_stdout: false
    )
  end
end
