defmodule Evaluate.Benchmark.Report do
  alias Evaluate.Benchmark.Fixture

  defstruct [
    :domain,
    :total,
    :scoreable_count,
    :compile_rate,
    :test_pass_rate,
    :by_category,
    :scores
  ]

  @type score :: %{
          fixture_id: String.t(),
          category: Fixture.category(),
          compiled: boolean() | nil,
          tests_passed: boolean() | nil,
          skipped: boolean()
        }

  @type category_stats :: %{
          total: non_neg_integer(),
          scoreable: non_neg_integer(),
          compiled: non_neg_integer(),
          passed: non_neg_integer()
        }

  @type t :: %__MODULE__{
          domain: atom(),
          total: non_neg_integer(),
          scoreable_count: non_neg_integer(),
          compile_rate: float(),
          test_pass_rate: float(),
          by_category: %{Fixture.category() => category_stats()},
          scores: [score()]
        }

  @spec build(atom(), [score()]) :: t()
  def build(domain, scores) do
    scoreable = Enum.reject(scores, & &1.skipped)
    compiled = Enum.count(scoreable, & &1.compiled)
    passed = Enum.count(scoreable, & &1.tests_passed)
    n = length(scoreable)

    %__MODULE__{
      domain: domain,
      total: length(scores),
      scoreable_count: n,
      compile_rate: safe_rate(compiled, n),
      test_pass_rate: safe_rate(passed, n),
      by_category: by_category(scores),
      scores: scores
    }
  end

  @spec summary(t()) :: String.t()
  def summary(%__MODULE__{} = r) do
    """
    Benchmark: #{r.domain}
    Total fixtures : #{r.total} (#{r.scoreable_count} sandbox-scoreable)
    Compile rate   : #{pct(r.compile_rate)}
    Test pass rate : #{pct(r.test_pass_rate)}

    By category:
    #{format_by_category(r.by_category)}
    """
  end

  defp by_category(scores) do
    scores
    |> Enum.group_by(& &1.category)
    |> Map.new(fn {cat, cat_scores} ->
      scoreable = Enum.reject(cat_scores, & &1.skipped)

      stats = %{
        total: length(cat_scores),
        scoreable: length(scoreable),
        compiled: Enum.count(scoreable, & &1.compiled),
        passed: Enum.count(scoreable, & &1.tests_passed)
      }

      {cat, stats}
    end)
  end

  defp format_by_category(by_cat) do
    by_cat
    |> Enum.sort_by(fn {cat, _} -> cat end)
    |> Enum.map_join("\n", fn {cat, s} ->
      "  #{cat}: #{s.passed}/#{s.scoreable} passed (#{s.total} total)"
    end)
  end

  defp safe_rate(_, 0), do: 0.0
  defp safe_rate(n, total), do: Float.round(n / total * 100, 1)

  defp pct(r), do: "#{r}%"
end
