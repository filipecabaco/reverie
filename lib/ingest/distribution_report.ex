defmodule Ingest.DistributionReport do
  @moduledoc """
  Computes statistics over a frozen dataset for quality review.

  Reports are domain-agnostic — they describe the candidates they receive,
  not the domain-specific meaning of those candidates. Domain-specific
  interpretation (e.g. "what is a good compile rate for Elixir?") belongs
  in the domain's evaluation configuration, not here.
  """

  defstruct [
    :total,
    :by_split,
    :task_type_dist,
    :difficulty_dist,
    :compile_rate,
    :test_pass_rate,
    :topic_coverage,
    :brief_coverage
  ]

  @type split_name :: :train | :validation | :test | :regression

  @type t :: %__MODULE__{
          total: non_neg_integer(),
          by_split: %{split_name() => non_neg_integer()},
          task_type_dist: %{String.t() => non_neg_integer()},
          difficulty_dist: %{String.t() => non_neg_integer()},
          compile_rate: float(),
          test_pass_rate: float(),
          topic_coverage: non_neg_integer(),
          brief_coverage: non_neg_integer()
        }

  @doc "Compute a distribution report from the split map."
  @spec compute(%{split_name() => [map()]}) :: t()
  def compute(splits) do
    all = splits |> Map.values() |> List.flatten()
    metas = Enum.map(all, &get_meta/1)

    %__MODULE__{
      total: length(all),
      by_split: Map.new(splits, fn {k, v} -> {k, length(v)} end),
      task_type_dist: count_field(metas, "task_type"),
      difficulty_dist: count_field(metas, "difficulty"),
      compile_rate: rate_field(metas, "compiled", true),
      test_pass_rate: rate_field(metas, "tests_passed", true),
      topic_coverage:
        metas
        |> Enum.map(&(&1["topic"] || &1[:topic]))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> length(),
      brief_coverage:
        metas
        |> Enum.map(&(&1["brief_id"] || &1[:brief_id]))
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> length()
    }
  end

  @doc "Render a human-readable summary."
  @spec summary(t()) :: String.t()
  def summary(%__MODULE__{} = r) do
    split_lines =
      r.by_split
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map_join("\n", fn {split, count} ->
        "  #{split}: #{count}"
      end)

    task_lines =
      r.task_type_dist
      |> Enum.sort_by(fn {_, v} -> -v end)
      |> Enum.map_join("\n", fn {type, count} ->
        "  #{type}: #{count}"
      end)

    """
    Dataset Distribution Report
    ===========================
    Total candidates : #{r.total}
    Topics covered   : #{r.topic_coverage}
    Briefs grounded  : #{r.brief_coverage}
    Compile rate     : #{pct(r.compile_rate)}
    Test pass rate   : #{pct(r.test_pass_rate)}

    By split:
    #{split_lines}

    By task type:
    #{task_lines}
    """
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp get_meta(%{"meta" => m}), do: m
  defp get_meta(%{meta: m}), do: m
  defp get_meta(_), do: %{}

  defp count_field(metas, field) do
    metas
    |> Enum.map(&fetch_field(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.frequencies()
  end

  defp rate_field(metas, field, target) do
    values =
      metas
      |> Enum.map(&fetch_field(&1, field))
      |> Enum.reject(&is_nil/1)

    case length(values) do
      0 -> 0.0
      n -> Float.round(Enum.count(values, &(&1 == target)) / n * 100, 1)
    end
  end

  defp fetch_field(map, string_key) do
    case Map.fetch(map, string_key) do
      {:ok, val} ->
        val

      :error ->
        atom_key = String.to_existing_atom(string_key)
        Map.get(map, atom_key)
    end
  rescue
    ArgumentError -> nil
  end

  defp pct(r), do: "#{r}%"
end
