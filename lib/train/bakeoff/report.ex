defmodule Train.Bakeoff.Report do
  @moduledoc """
  Comparison report across all bake-off candidates.

  Ranks candidates by a weighted score:
    - test_pass_rate   40%
    - compile_rate     30%
    - commercial_ok    20%  (binary gate — non-commercial = 0)
    - memory_fit       10%  (inverse of estimated VRAM, normalised)

  The recommendation is the highest-scoring eligible candidate.
  The report is serialisable to JSON for audit trail storage.
  """

  alias Evaluate.Benchmark.Report, as: BenchmarkReport
  alias Train.ModelCandidate

  defstruct [:domain, :candidates, :scores, :recommendation, :ran_at]

  @type candidate_score :: %{
          candidate: ModelCandidate.t(),
          benchmark: BenchmarkReport.t(),
          weighted_score: float()
        }

  @type t :: %__MODULE__{
          domain: atom(),
          candidates: [ModelCandidate.t()],
          scores: [candidate_score()],
          recommendation: ModelCandidate.t() | nil,
          ran_at: DateTime.t()
        }

  @spec build(atom(), [{ModelCandidate.t(), BenchmarkReport.t()}], DateTime.t()) :: t()
  def build(domain, candidate_results, ran_at \\ DateTime.utc_now()) do
    scores =
      candidate_results
      |> Enum.map(fn {candidate, benchmark} ->
        %{
          candidate: candidate,
          benchmark: benchmark,
          weighted_score: weighted_score(candidate, benchmark)
        }
      end)
      |> Enum.sort_by(& &1.weighted_score, :desc)

    recommendation =
      scores
      |> Enum.find(&ModelCandidate.eligible?(&1.candidate))
      |> case do
        nil -> nil
        entry -> entry.candidate
      end

    %__MODULE__{
      domain: domain,
      candidates: Enum.map(candidate_results, &elem(&1, 0)),
      scores: scores,
      recommendation: recommendation,
      ran_at: ran_at
    }
  end

  @spec summary(t()) :: String.t()
  def summary(%__MODULE__{} = r) do
    rows =
      r.scores
      |> Enum.map_join("\n", fn %{candidate: c, benchmark: b, weighted_score: s} ->
        eligibility = if ModelCandidate.eligible?(c), do: "✓", else: "✗"

        "  #{eligibility} #{String.pad_trailing(c.name, 28)} " <>
          "compile=#{pct(b.compile_rate)} " <>
          "test=#{pct(b.test_pass_rate)} " <>
          "vram=#{vram(c)} " <>
          "score=#{Float.round(s, 2)}"
      end)

    recommendation =
      case r.recommendation do
        nil -> "  NONE — no eligible candidate passed all gates"
        c -> "  #{c.id}"
      end

    """
    Bake-off: #{r.domain} (#{DateTime.to_iso8601(r.ran_at)})
    #{rows}

    Recommendation:
    #{recommendation}
    """
  end

  @spec to_json(t()) :: {:ok, String.t()} | {:error, term()}
  def to_json(%__MODULE__{} = r) do
    Jason.encode(%{
      domain: r.domain,
      ran_at: DateTime.to_iso8601(r.ran_at),
      recommendation: r.recommendation && r.recommendation.id,
      scores:
        Enum.map(r.scores, fn %{candidate: c, benchmark: b, weighted_score: s} ->
          %{
            candidate_id: c.id,
            compile_rate: b.compile_rate,
            test_pass_rate: b.test_pass_rate,
            scoreable_count: b.scoreable_count,
            weighted_score: Float.round(s, 4),
            eligible: ModelCandidate.eligible?(c)
          }
        end)
    })
  end

  defp weighted_score(candidate, benchmark) do
    eligibility = if ModelCandidate.eligible?(candidate), do: 1.0, else: 0.0

    memory_score =
      case candidate.estimated_vram_4bit_gb do
        nil -> 0.5
        vram -> max(0.0, 1.0 - vram / 24.0)
      end

    benchmark.test_pass_rate / 100 * 0.40 +
      benchmark.compile_rate / 100 * 0.30 +
      eligibility * 0.20 +
      memory_score * 0.10
  end

  defp pct(r), do: "#{r}%"
  defp vram(c), do: if(c.estimated_vram_4bit_gb, do: "#{c.estimated_vram_4bit_gb}GB", else: "?")
end
