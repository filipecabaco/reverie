defmodule Evaluate.PromotionGateTest do
  use ExUnit.Case, async: true

  alias Evaluate.Benchmark.Report
  alias Evaluate.FourWay.Result
  alias Evaluate.PromotionGate
  alias Train.Bakeoff.Compatibility

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp result(adapter_gain, adapter_retrieval_gain) do
    base_rate = 50.0
    base_ret_rate = 60.0

    reports = %{
      base: fake_report(base_rate),
      base_retrieval: fake_report(base_ret_rate),
      adapter: fake_report(base_rate + adapter_gain),
      adapter_retrieval: fake_report(base_ret_rate + adapter_retrieval_gain)
    }

    Result.build(:elixir, reports)
  end

  defp fake_report(test_pass_rate) do
    %Report{
      domain: :elixir,
      total: 20,
      scoreable_count: 15,
      compile_rate: 90.0,
      test_pass_rate: test_pass_rate,
      by_category: %{},
      scores: []
    }
  end

  defp passed_compat do
    Compatibility.gates()
    |> Enum.reduce(Compatibility.new(), fn gate, acc ->
      Compatibility.mark(acc, gate, :pass)
    end)
  end

  defp failed_compat do
    Compatibility.new()
    |> Compatibility.mark(:base_loads, :fail, "OOM on startup")
  end

  # ---------------------------------------------------------------------------
  # Decision logic
  # ---------------------------------------------------------------------------

  describe "evaluate/2 — :promote" do
    test "promotes when adapter beats base and retrieval-corrected gain holds" do
      eval = PromotionGate.evaluate(result(10.0, 5.0))
      assert eval.decision == :promote
    end

    test "promotes with all optional gates passing" do
      eval =
        PromotionGate.evaluate(result(10.0, 5.0),
          regression_report: fake_report(90.0),
          base_regression_rate: 90.0,
          compatibility: passed_compat()
        )

      assert eval.decision == :promote
    end
  end

  describe "evaluate/2 — :reject" do
    test "rejects when adapter does not beat base" do
      eval = PromotionGate.evaluate(result(-5.0, -2.0))
      assert eval.decision == :reject
    end

    test "rejects when retrieval-corrected gain is absent" do
      # Adapter beats base alone, but the gain disappears once retrieval is added.
      eval = PromotionGate.evaluate(result(10.0, -1.0))
      assert eval.decision == :reject
    end

    test "rejects when regression exceeds threshold" do
      eval =
        PromotionGate.evaluate(result(10.0, 5.0),
          regression_report: fake_report(70.0),
          base_regression_rate: 90.0,
          regression_threshold: 5.0
        )

      assert eval.decision == :reject
    end

    test "rejects when compatibility checklist has failures" do
      eval =
        PromotionGate.evaluate(result(10.0, 5.0),
          compatibility: failed_compat()
        )

      assert eval.decision == :reject
    end
  end

  describe "evaluate/2 — :incomplete" do
    test "promotes (not incomplete) when optional gates not provided" do
      # No regression/compat/artifact → all :not_run → does not block promotion
      eval = PromotionGate.evaluate(result(10.0, 5.0))
      assert eval.decision == :promote
    end

    test "incomplete when compatibility checklist has pending gates" do
      # Compat was explicitly provided but has pending items → :not_evaluated → :incomplete
      partial =
        Compatibility.new()
        |> Compatibility.mark(:base_loads, :pass)

      eval = PromotionGate.evaluate(result(10.0, 5.0), compatibility: partial)
      assert eval.decision == :incomplete
    end
  end

  # ---------------------------------------------------------------------------
  # Gate details
  # ---------------------------------------------------------------------------

  describe "gate structure" do
    test "returns a gate result for each check" do
      eval = PromotionGate.evaluate(result(10.0, 5.0))
      gate_names = Enum.map(eval.gates, & &1.gate)

      assert :domain_improvement in gate_names
      assert :retrieval_corrected in gate_names
      assert :regression in gate_names
      assert :compatibility in gate_names
      assert :artifact in gate_names
    end

    test "domain_improvement gate passes with positive adapter_gain" do
      eval = PromotionGate.evaluate(result(15.0, 10.0))
      gate = Enum.find(eval.gates, &(&1.gate == :domain_improvement))
      assert gate.status == :pass
    end

    test "domain_improvement gate fails with negative adapter_gain" do
      eval = PromotionGate.evaluate(result(-5.0, 0.0))
      gate = Enum.find(eval.gates, &(&1.gate == :domain_improvement))
      assert gate.status == :fail
    end

    test "regression gate is :not_run when no report provided" do
      eval = PromotionGate.evaluate(result(10.0, 5.0))
      gate = Enum.find(eval.gates, &(&1.gate == :regression))
      assert gate.status == :not_run
    end

    test "regression gate passes when drop is within threshold" do
      eval =
        PromotionGate.evaluate(result(10.0, 5.0),
          regression_report: fake_report(87.0),
          base_regression_rate: 90.0,
          regression_threshold: 5.0
        )

      gate = Enum.find(eval.gates, &(&1.gate == :regression))
      assert gate.status == :pass
    end
  end

  # ---------------------------------------------------------------------------
  # Summary
  # ---------------------------------------------------------------------------

  describe "summary" do
    test "summary string contains decision and gate names" do
      eval = PromotionGate.evaluate(result(10.0, 5.0))
      assert String.contains?(eval.summary, "PROMOTE")
      assert String.contains?(eval.summary, "domain_improvement")
    end

    test "summary contains PROMOTE for a fully passing eval" do
      eval =
        PromotionGate.evaluate(result(10.0, 5.0),
          regression_report: fake_report(90.0),
          base_regression_rate: 90.0,
          compatibility: passed_compat()
        )

      assert String.contains?(eval.summary, "PROMOTE")
    end

    test "summary contains REJECT for a failing eval" do
      eval = PromotionGate.evaluate(result(-5.0, -3.0))
      assert String.contains?(eval.summary, "REJECT")
    end
  end
end
