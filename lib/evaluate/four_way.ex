defmodule Evaluate.FourWay do
  @moduledoc """
  Runs the four-way evaluation across all benchmark fixtures for a domain (§11.2).

  The four conditions are driven by injectable responder functions so the harness
  is model-agnostic — any inference backend (local, API, vLLM, Bumblebee) can be
  plugged in. Tests use stub responders that return canned code.

  Usage:

      responders = %{
        base:              fn prompt -> call_base_model(prompt) end,
        base_retrieval:    fn prompt -> call_base_model(with_rag(prompt)) end,
        adapter:           fn prompt -> call_adapter(prompt) end,
        adapter_retrieval: fn prompt -> call_adapter(with_rag(prompt)) end
      }

      result = Evaluate.FourWay.run(:elixir, responders)
      IO.puts(Evaluate.FourWay.Result.summary(result))
  """

  alias Evaluate.Benchmark
  alias Evaluate.FourWay.Result

  @type responder :: (String.t() -> String.t())
  @type responders :: %{
          base: responder(),
          base_retrieval: responder(),
          adapter: responder(),
          adapter_retrieval: responder()
        }

  @doc """
  Run all four conditions against the domain's benchmark fixtures.

  Options:
    - `:domain` — benchmark domain (required, defaults to the `domain` arg)
    - `:only_scoreable` — skip non-sandbox-scoreable fixtures (default true)

  Each condition runs `Evaluate.Benchmark.run/2` independently and returns a
  `Benchmark.Report`. The four reports are assembled into a `FourWay.Result`.
  """
  @spec run(atom(), responders(), keyword()) :: Result.t()
  def run(domain, responders, _opts \\ []) do
    validate_responders!(responders)

    reports =
      Map.new(Result.conditions(), fn condition ->
        responder = Map.fetch!(responders, condition)

        :telemetry.execute([:reverie, :eval, :condition_start], %{}, %{
          domain: domain,
          condition: condition
        })

        report = Benchmark.run(domain, responder)

        :telemetry.execute([:reverie, :eval, :condition_done], %{}, %{
          domain: domain,
          condition: condition,
          compile_rate: report.compile_rate,
          test_pass_rate: report.test_pass_rate
        })

        {condition, report}
      end)

    Result.build(domain, reports)
  end

  @doc """
  Run a single condition for spot-checking or incremental evaluation.
  Returns a `Benchmark.Report`.
  """
  @spec run_condition(atom(), atom(), responder(), keyword()) :: Evaluate.Benchmark.Report.t()
  def run_condition(domain, condition, responder, _opts \\ [])
      when condition in [:base, :base_retrieval, :adapter, :adapter_retrieval] do
    Benchmark.run(domain, responder)
  end

  defp validate_responders!(responders) do
    missing = Result.conditions() -- Map.keys(responders)

    unless missing == [] do
      raise ArgumentError,
            "missing responders for conditions: #{inspect(missing)}"
    end
  end
end
