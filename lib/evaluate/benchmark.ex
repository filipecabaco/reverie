defmodule Evaluate.Benchmark do
  @moduledoc """
  Loads benchmark fixtures and scores model responses against them.

  Usage (once a model responder is available):

      responder = fn prompt -> call_model(prompt) end
      report = Evaluate.Benchmark.run(:elixir, responder)
      IO.puts(Evaluate.Benchmark.Report.summary(report))

  Scoring a single pre-existing response:

      {:ok, score} = Evaluate.Benchmark.score(fixture, code)
  """

  alias DatasetGen.Sandbox
  alias Evaluate.Benchmark.{Fixture, Fixtures, Report}

  @doc "Load all fixtures for a domain."
  @spec load(atom()) :: [Fixture.t()]
  def load(domain), do: Fixtures.for_domain(domain)

  @doc """
  Score a model's code response against a fixture.
  Returns a score map. Skips sandbox for non-scoreable fixtures.
  """
  @spec score(Fixture.t(), String.t()) :: {:ok, Report.score()} | {:error, term()}
  def score(%Fixture{scoreable: false} = f, _code) do
    {:ok,
     %{fixture_id: f.id, category: f.category, compiled: nil, tests_passed: nil, skipped: true}}
  end

  def score(%Fixture{scoreable: true} = f, code) do
    case Sandbox.validate(code, f.test_code) do
      {:ok, verdict} ->
        {:ok,
         %{
           fixture_id: f.id,
           category: f.category,
           compiled: verdict.compiled,
           tests_passed: verdict.tests_passed,
           skipped: false
         }}

      {:error, :timeout} ->
        {:ok,
         %{
           fixture_id: f.id,
           category: f.category,
           compiled: false,
           tests_passed: false,
           skipped: false
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Run all fixtures for a domain against a responder function.
  The responder receives a prompt string and must return a code string.
  """
  @spec run(atom(), (String.t() -> String.t())) :: Report.t()
  def run(domain, responder) when is_function(responder, 1) do
    scores =
      domain
      |> load()
      |> Enum.map(fn fixture ->
        code = responder.(fixture.prompt)
        {:ok, score} = score(fixture, code)
        score
      end)

    Report.build(domain, scores)
  end
end
