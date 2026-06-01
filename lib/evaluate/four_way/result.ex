defmodule Evaluate.FourWay.Result do
  @moduledoc """
  Structured result of a four-way evaluation (§11.2).

  Four conditions, each a full benchmark run:
    :base              — base model, no retrieval
    :base_retrieval    — base model + RAG from domain corpus
    :adapter           — adapter-tuned model, no retrieval
    :adapter_retrieval — adapter-tuned model + RAG

  The `comparison` map gives the numbers that matter for promotion:
    adapter_gain           — adapter.test_pass_rate - base.test_pass_rate
    adapter_retrieval_gain — adapter_retrieval - base_retrieval (the anti-leakage check)
    retrieval_gain_base    — how much retrieval alone helps the base
    retrieval_gain_adapter — how much retrieval helps the adapter on top of tuning

  A genuine adapter improvement shows positive gains in BOTH `adapter_gain`
  and `adapter_retrieval_gain`. If only `adapter_gain` is positive while
  `adapter_retrieval_gain` is flat, the base already captures what the adapter
  adds once retrieval is in place — the fine-tuning is redundant.
  """

  alias Evaluate.Benchmark.Report

  @conditions [:base, :base_retrieval, :adapter, :adapter_retrieval]

  defstruct [:domain, :base, :base_retrieval, :adapter, :adapter_retrieval, :comparison]

  @type t :: %__MODULE__{
          domain: atom(),
          base: Report.t(),
          base_retrieval: Report.t(),
          adapter: Report.t(),
          adapter_retrieval: Report.t(),
          comparison: map()
        }

  @spec build(atom(), %{atom() => Report.t()}) :: t()
  def build(domain, reports) do
    base = reports[:base]
    base_ret = reports[:base_retrieval]
    adapter = reports[:adapter]
    adapter_ret = reports[:adapter_retrieval]

    comparison = %{
      adapter_gain: delta(adapter, base),
      adapter_retrieval_gain: delta(adapter_ret, base_ret),
      retrieval_gain_base: delta(base_ret, base),
      retrieval_gain_adapter: delta(adapter_ret, adapter),
      adapter_beats_base: adapter.test_pass_rate > base.test_pass_rate,
      adapter_beats_base_retrieval: adapter.test_pass_rate > base_ret.test_pass_rate,
      adapter_retrieval_beats_base_retrieval: adapter_ret.test_pass_rate > base_ret.test_pass_rate
    }

    %__MODULE__{
      domain: domain,
      base: base,
      base_retrieval: base_ret,
      adapter: adapter,
      adapter_retrieval: adapter_ret,
      comparison: comparison
    }
  end

  @doc "All four condition keys."
  @spec conditions() :: [atom()]
  def conditions, do: @conditions

  @doc "Render a comparison table."
  @spec summary(t()) :: String.t()
  def summary(%__MODULE__{} = r) do
    rows =
      @conditions
      |> Enum.map(fn cond ->
        report = Map.get(r, cond)
        gain = gain_label(r.comparison, cond)

        "  #{String.pad_trailing(to_string(cond), 20)} " <>
          "compile=#{pct(report.compile_rate)} " <>
          "test=#{pct(report.test_pass_rate)} " <>
          gain
      end)
      |> Enum.join("\n")

    verdict = if r.comparison.adapter_beats_base, do: "ADAPTER IMPROVES", else: "NO IMPROVEMENT"

    """
    Four-Way Evaluation: #{r.domain}
    #{rows}

    Adapter gain (test pass rate): #{signed(r.comparison.adapter_gain)}%
    Retrieval-corrected gain:      #{signed(r.comparison.adapter_retrieval_gain)}%
    Verdict: #{verdict}
    """
  end

  defp delta(a, b), do: Float.round(a.test_pass_rate - b.test_pass_rate, 1)

  defp gain_label(comparison, :adapter), do: "Δ=#{signed(comparison.adapter_gain)}%"

  defp gain_label(comparison, :adapter_retrieval),
    do: "Δ=#{signed(comparison.adapter_retrieval_gain)}%"

  defp gain_label(_, _), do: ""

  defp pct(r), do: "#{r}%"
  defp signed(n) when n >= 0, do: "+#{n}"
  defp signed(n), do: "#{n}"
end
