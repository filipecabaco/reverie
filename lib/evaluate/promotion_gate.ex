defmodule Evaluate.PromotionGate do
  @moduledoc """
  Decides whether a trained adapter is ready for production (§11.6).

  All of the following must be true to promote:
    1. Adapter improves domain test_pass_rate over the base model.
    2. Adapter+retrieval improves over base+retrieval (anti-leakage check —
       ensures gains aren't just from retrieval that the base already captures).
    3. General regression is within the acceptable threshold.
    4. If a compatibility checklist was run, all non-skipped gates passed.
    5. Artifact directory contains all required files.

  Gates 3–5 are optional — if the relevant data is not provided (nil), the gate
  is skipped with a :not_evaluated status rather than a hard failure. This lets
  the harness be used for partial evaluation during development.
  """

  alias Evaluate.FourWay.Result
  alias Train.Bakeoff.Compatibility
  alias Train.Artifacts

  # :pass         — ran and passed
  # :fail         — ran and failed (blocks promotion)
  # :not_evaluated — explicitly provided but incomplete (e.g. pending compat items)
  # :not_run      — input was nil; gate was skipped (does not block promotion)
  @type gate_status :: :pass | :fail | :not_evaluated | :not_run
  @type gate_result :: %{gate: atom(), status: gate_status(), detail: String.t() | nil}
  @type decision :: :promote | :reject | :incomplete

  @type evaluation :: %{
          decision: decision(),
          gates: [gate_result()],
          summary: String.t()
        }

  @doc """
  Evaluate the promotion gates.

  Options:
    - `:regression_report`     — `Benchmark.Report` for the regression split (nil = skip gate)
    - `:regression_threshold`  — maximum allowed drop in test_pass_rate vs baseline (default 5.0%)
    - `:compatibility`         — completed `Compatibility.t()` checklist (nil = skip gate)
    - `:artifact_path`         — path to adapter artifact directory (nil = skip gate)
    - `:base_regression_rate`  — baseline regression test_pass_rate to compare against
  """
  @spec evaluate(Result.t(), keyword()) :: evaluation()
  def evaluate(%Result{} = result, opts \\ []) do
    gates = [
      domain_improvement_gate(result),
      retrieval_corrected_gate(result),
      regression_gate(result, opts),
      compatibility_gate(opts),
      artifact_gate(opts)
    ]

    decision = derive_decision(gates)

    %{
      decision: decision,
      gates: gates,
      summary: format_summary(result, gates, decision)
    }
  end

  # ---------------------------------------------------------------------------
  # Gates
  # ---------------------------------------------------------------------------

  defp domain_improvement_gate(%Result{comparison: c}) do
    if c.adapter_beats_base do
      gate(:domain_improvement, :pass, "adapter +#{c.adapter_gain}% over base")
    else
      gate(:domain_improvement, :fail, "adapter #{c.adapter_gain}% vs base — no improvement")
    end
  end

  defp retrieval_corrected_gate(%Result{comparison: c}) do
    if c.adapter_retrieval_beats_base_retrieval do
      gate(:retrieval_corrected, :pass, "adapter+retrieval +#{c.adapter_retrieval_gain}%")
    else
      gate(
        :retrieval_corrected,
        :fail,
        "adapter+retrieval #{c.adapter_retrieval_gain}% — gain disappears with retrieval"
      )
    end
  end

  defp regression_gate(_result, opts) do
    regression_report = opts[:regression_report]
    base_rate = opts[:base_regression_rate]
    threshold = Keyword.get(opts, :regression_threshold, 5.0)

    cond do
      is_nil(regression_report) or is_nil(base_rate) ->
        gate(:regression, :not_run, "regression report not provided (skipped)")

      base_rate - regression_report.test_pass_rate <= threshold ->
        gate(:regression, :pass, "regression within #{threshold}% threshold")

      true ->
        drop = Float.round(base_rate - regression_report.test_pass_rate, 1)
        gate(:regression, :fail, "regression dropped #{drop}% (threshold: #{threshold}%)")
    end
  end

  defp compatibility_gate(opts) do
    case opts[:compatibility] do
      nil ->
        gate(:compatibility, :not_run, "compatibility checklist not provided (skipped)")

      checklist ->
        failures = Compatibility.failures(checklist)
        pending = Compatibility.pending(checklist)

        cond do
          failures != [] ->
            gate(:compatibility, :fail, "failed gates: #{inspect(failures)}")

          pending != [] ->
            gate(:compatibility, :not_evaluated, "#{length(pending)} gates still pending")

          true ->
            gate(:compatibility, :pass, "all compatibility gates passed")
        end
    end
  end

  defp artifact_gate(opts) do
    case opts[:artifact_path] do
      nil ->
        gate(:artifact, :not_run, "artifact path not provided (skipped)")

      path ->
        case Artifacts.verify(path) do
          :ok -> gate(:artifact, :pass, "artifact verified at #{path}")
          {:error, reason} -> gate(:artifact, :fail, inspect(reason))
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Decision
  # ---------------------------------------------------------------------------

  defp derive_decision(gates) do
    cond do
      Enum.any?(gates, &(&1.status == :fail)) ->
        :reject

      Enum.any?(gates, &(&1.status == :not_evaluated)) ->
        # A gate was explicitly run but returned incomplete (e.g. pending compat items)
        :incomplete

      true ->
        # :pass and :not_run gates — :not_run gates were skipped by the caller and
        # do not block promotion
        :promote
    end
  end

  # ---------------------------------------------------------------------------
  # Formatting
  # ---------------------------------------------------------------------------

  defp format_summary(%Result{domain: domain}, gates, decision) do
    gate_lines =
      Enum.map_join(gates, "\n", fn g ->
        icon = icon(g.status)
        detail = if g.detail, do: " — #{g.detail}", else: ""
        "  #{icon} #{g.gate}#{detail}"
      end)

    """
    Promotion Gate: #{domain}
    #{gate_lines}

    Decision: #{String.upcase(to_string(decision))}
    """
  end

  defp gate(name, status, detail), do: %{gate: name, status: status, detail: detail}

  defp icon(:pass), do: "✓"
  defp icon(:fail), do: "✗"
  defp icon(:not_evaluated), do: "?"
  defp icon(:not_run), do: "–"
end
