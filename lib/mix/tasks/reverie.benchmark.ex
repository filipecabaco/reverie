defmodule Mix.Tasks.Reverie.Benchmark do
  use Mix.Task

  @shortdoc "Run the benchmark for a domain using Claude as the responder"

  @moduledoc """
  Runs the benchmark fixtures for a domain using Claude as the responder.
  Useful for measuring a baseline before training an adapter.

  ## Usage

      mix reverie.benchmark --domain <domain> --backend cli
      mix reverie.benchmark --domain <domain> --backend api

  ## Options

      --domain    Domain key. Required.
      --model     Claude model to use (api backend only). Default: claude-haiku-4-5
      --backend   api (default, requires credits) or cli (uses claude CLI session)
      --out       Write JSON report to file (optional)
  """

  @switches [domain: :string, model: :string, backend: :string, out: :string]
  @defaults [model: "claude-haiku-4-5", backend: "api"]

  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    opts = Keyword.merge(@defaults, opts)

    unless opts[:domain], do: Mix.raise("--domain is required. Run `mix reverie.domain` to see available domains.")

    backend = opts[:backend]
    domain = Mix.Tasks.Reverie.Helpers.resolve_domain(opts[:domain])
    model = opts[:model]

    if backend == "api", do: ensure_api_key!()

    fixtures = Evaluate.Benchmark.Fixtures.for_domain(domain)
    total = length(fixtures)
    scoreable = Enum.count(fixtures, & &1.scoreable)

    Mix.shell().info(
      "📊 Benchmark: :#{domain} — #{total} fixtures (#{scoreable} sandbox-scoreable)"
    )

    Mix.shell().info(
      "   Backend: #{backend}#{if backend == "api", do: "  Model: #{model}", else: ""}\n"
    )

    responder = build_responder(backend, model)
    report = Evaluate.Benchmark.run(domain, responder)

    Mix.shell().info(Evaluate.Benchmark.Report.summary(report))

    if path = opts[:out] do
      File.write!(path, Jason.encode!(report, pretty: true))
      Mix.shell().info("Report written to #{path}")
    end
  end

  defp build_responder("cli", _model) do
    fn prompt ->
      case Mix.Tasks.Reverie.Helpers.run_claude(prompt) do
        {output, 0} -> String.trim(output)
        _ -> ""
      end
    end
  end

  defp build_responder("api", model) do
    fn prompt ->
      body = %{
        model: model,
        max_tokens: 2048,
        system:
          "You are an expert. Respond with working code only — no explanation unless asked.",
        messages: [%{role: "user", content: prompt}]
      }

      case Req.post("https://api.anthropic.com/v1/messages",
             json: body,
             headers: [
               {"x-api-key", System.get_env("ANTHROPIC_API_KEY", "")},
               {"anthropic-version", "2023-06-01"}
             ],
             receive_timeout: 30_000
           ) do
        {:ok, %{status: 200, body: %{"content" => [%{"text" => text} | _]}}} -> text
        _ -> ""
      end
    end
  end

  defp ensure_api_key! do
    if System.get_env("ANTHROPIC_API_KEY") in [nil, ""] do
      Mix.raise("ANTHROPIC_API_KEY is not set.\nRun: export $(grep -v '^#' .env | xargs)")
    end
  end
end
