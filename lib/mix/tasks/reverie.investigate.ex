defmodule Mix.Tasks.Reverie.Investigate do
  use Mix.Task

  @shortdoc "Research topics and store briefs in the domain corpus"

  @moduledoc """
  Research topics and store briefs in the domain corpus.

  --backend cli: asks Claude directly for facts (works without a populated
    corpus — great for getting started).

  --backend api: uses the self-reflective RAG loop against the local SQLite
    corpus. Requires the corpus to have been populated first via fetchers.

  When --topic is omitted, the teacher picks a fresh high-value topic each loop.
  Use --loops to run multiple investigations in one command.

  ## Usage

      mix reverie.investigate --domain supabase --loops 5
      mix reverie.investigate --domain elixir --topic "GenServer timeouts"
      mix reverie.investigate --domain supabase --loops 10 --backend cli

  ## Options

      --domain    Domain key (elixir, postgres, supabase, ...). Default: elixir
      --topic     Fixed topic for every loop. Omit to let the teacher choose each time.
      --loops     Number of investigations to run. Default: 1
      --backend   cli (uses Claude CLI, no corpus needed) or api (uses local corpus)
      --data-dir  Root data directory. Default: data
  """

  @switches [
    domain: :string,
    topic: :string,
    backend: :string,
    data_dir: :string,
    loops: :integer
  ]
  @defaults [domain: "elixir", backend: "cli", data_dir: "data", loops: 1]

  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    opts = Keyword.merge(@defaults, opts)

    domain = Mix.Tasks.Reverie.Helpers.resolve_domain(opts[:domain])
    backend = opts[:backend]
    data_dir = opts[:data_dir]
    loops = opts[:loops]
    fixed_topic = opts[:topic]

    {:ok, conn} = Corpus.Store.open(domain, data_dir)

    # Fetch all topics in one shot before the loop so we get a diverse list
    # rather than the same "most important" topic repeated every time.
    topics =
      if fixed_topic do
        List.duplicate(fixed_topic, loops)
      else
        fetched = Mix.Tasks.Reverie.Helpers.suggest_topics(domain, backend, loops)
        Mix.shell().info("🤖 Topics planned: #{Enum.join(fetched, ", ")}\n")
        fetched
      end

    results =
      topics
      |> Enum.with_index(1)
      |> Enum.map(fn {topic, i} ->
        if loops > 1, do: Mix.shell().info("[#{i}/#{loops}]")
        Mix.shell().info("🔍 #{topic}")

        result =
          case backend do
            "cli" -> investigate_via_cli(topic, domain, conn)
            _ -> investigate_via_corpus(topic, domain, conn)
          end

        case result do
          {:ok, brief} ->
            Mix.shell().info("   ✓ saved (#{length(brief.facts)} facts)")
            :ok

          {:error, {:coverage_gap, _}} ->
            Mix.shell().info("   – no evidence found, skipped")
            :skipped

          {:error, {:cli_error, code, msg}} ->
            Mix.shell().error("   ✗ CLI error (exit #{code}): #{String.trim(msg)}")
            :error

          {:error, reason} ->
            Mix.shell().error("   ✗ #{inspect(reason)}")
            :error
        end
      end)

    if loops > 1 do
      ok = Enum.count(results, &(&1 == :ok))
      skipped = Enum.count(results, &(&1 == :skipped))
      errors = Enum.count(results, &(&1 == :error))
      Mix.shell().info("\nDone: #{ok} saved, #{skipped} skipped, #{errors} errors")
    end
  after
    :ok
  end

  # ---------------------------------------------------------------------------
  # CLI backend — ask Claude directly, no local corpus needed
  # ---------------------------------------------------------------------------

  defp investigate_via_cli(topic, domain, conn) do
    prompt = """
    You are a technical expert on #{domain}.

    List 8 important, specific facts a developer must know about "#{topic}" in #{domain}.

    Format: one fact per line, starting with "- ". Be concrete and accurate.
    No headings, no introduction, just the facts.
    """

    case Mix.Tasks.Reverie.Helpers.run_claude(prompt) do
      {output, 0} ->
        facts =
          output
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.filter(&String.starts_with?(&1, "- "))
          |> Enum.map(&String.trim_leading(&1, "- "))
          |> Enum.reject(&(&1 == ""))

        if facts == [] do
          {:error, {:coverage_gap, topic}}
        else
          brief = %Research.Brief{
            id: "brief-#{domain}-#{slug(topic)}-#{:os.system_time(:millisecond)}",
            domain: domain,
            topic: topic,
            facts: facts,
            examples: nil,
            prohibited_patterns: nil,
            sources: [
              %{
                kind: :official_docs,
                reference: "claude-cli-synthesis",
                retrieved_at: DateTime.utc_now()
              }
            ],
            package_versions: %{},
            created_at: DateTime.utc_now(),
            expires_at: nil,
            status: :usable_for_generation
          }

          Research.Coordinator.save_brief(brief, conn: conn)
        end

      {error, code} ->
        {:error, {:cli_error, code, error}}
    end
  end

  # ---------------------------------------------------------------------------
  # API / corpus backend — RAG loop against local SQLite corpus
  # ---------------------------------------------------------------------------

  defp investigate_via_corpus(topic, domain, conn) do
    Research.Coordinator.investigate_and_save(topic, conn: conn, domain: domain)
  end

  defp slug(text) do
    text |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
  end
end
