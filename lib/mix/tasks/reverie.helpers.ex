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
  Ask the teacher for a list of `count` diverse topics for a domain.
  Returns a list of topic strings, shuffled so repeated calls get different orders.
  """
  def suggest_topics(domain, backend, count \\ 1) do
    prompt = """
    List #{max(count, 10)} specific, practical topics a developer needs to understand \
    when working with #{domain}.

    Requirements:
    - Each topic on its own line, starting with "- "
    - 2-6 words per topic, no punctuation at the end
    - Cover a diverse range: core concepts, common pitfalls, advanced patterns, \
    debugging techniques, performance, security
    - Be specific (e.g. "Row Level Security policies" not just "security")
    - No duplicates, no introductory text
    """

    topics =
      case backend do
        "cli" -> fetch_topics_cli(prompt)
        _ -> fetch_topics_api(prompt)
      end

    topics |> Enum.shuffle() |> Enum.take(count)
  end

  # Keep the single-topic helper for backwards compat
  def suggest_topic(domain, backend) do
    suggest_topics(domain, backend, 1) |> hd()
  end

  defp fetch_topics_cli(prompt) do
    case run_claude(prompt) do
      {output, 0} ->
        parse_topic_list(output)

      {error, code} ->
        Mix.raise("CLI error (exit #{code}): #{error}\nPass --topic to skip this step.")
    end
  end

  defp fetch_topics_api(prompt) do
    api_key = System.get_env("ANTHROPIC_API_KEY", "")

    body = %{
      model: "claude-haiku-4-5",
      max_tokens: 512,
      system:
        "Reply with a plain bulleted list — one topic per line, starting with '- '. No other text.",
      messages: [%{role: "user", content: prompt}]
    }

    case Req.post("https://api.anthropic.com/v1/messages",
           json: body,
           headers: [{"x-api-key", api_key}, {"anthropic-version", "2023-06-01"}],
           receive_timeout: 20_000
         ) do
      {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} ->
        parse_topic_list(text)

      {:ok, %{status: 400, body: %{"error" => %{"message" => msg}}}} ->
        Mix.raise(
          "API error: #{msg}\n\nAdd credits at console.anthropic.com or use --backend cli"
        )

      {:ok, %{status: status, body: body}} ->
        Mix.raise("API returned #{status}: #{inspect(body)}")

      {:error, reason} ->
        Mix.raise("Request failed: #{inspect(reason)}")
    end
  end

  defp parse_topic_list(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "- "))
    |> Enum.map(&String.trim_leading(&1, "- "))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
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

    # </dev/null closes stdin (prevents "no stdin data" warning).
    # 2>/dev/null suppresses the 3s stdin-wait warning from stderr.
    # Real errors still surface via non-zero exit codes.
    System.cmd("sh", ["-c", "claude -p \"$REVERIE_PROMPT\" </dev/null 2>/dev/null"],
      env: env,
      stderr_to_stdout: false
    )
  end
end
