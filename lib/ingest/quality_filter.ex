defmodule Ingest.QualityFilter do
  @moduledoc """
  Quality gates applied to generated candidates before splitting.

  All filters are optional and configured via opts:
    :require_compiled    — drop candidates where meta.compiled == false (default true for code tasks)
    :require_tests_pass  — drop candidates where meta.tests_passed == false
    :min_answer_bytes    — minimum byte length of the answer
    :max_answer_bytes    — maximum byte length of the answer
    :allowed_task_types  — whitelist of task type atoms; nil = allow all
    :custom              — a (candidate -> boolean) function for domain-specific checks

  Candidates without a `compiled` field (explanation tasks) are treated as passing
  the compiled gate unless :require_compiled is :code_only.
  """

  @default_min_answer_bytes 50

  @type candidate :: map()
  @type filter_opts :: keyword()

  @doc """
  Apply all configured gates. Returns `{:ok, kept}` where `kept` is the
  subset that passed every gate, and emits a summary.
  """
  @spec filter([candidate()], filter_opts()) :: {:ok, [candidate()], map()}
  def filter(candidates, opts \\ []) do
    gates = build_gates(opts)
    {kept, dropped} = Enum.split_with(candidates, &passes_all?(&1, gates))

    summary = %{
      total: length(candidates),
      kept: length(kept),
      dropped: length(dropped),
      drop_rate: safe_rate(length(dropped), length(candidates))
    }

    {:ok, kept, summary}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp build_gates(opts) do
    [
      {:compiled, Keyword.get(opts, :require_compiled, true)},
      {:tests_pass, Keyword.get(opts, :require_tests_pass, false)},
      {:min_bytes, Keyword.get(opts, :min_answer_bytes, @default_min_answer_bytes)},
      {:max_bytes, Keyword.get(opts, :max_answer_bytes, nil)},
      {:task_types, Keyword.get(opts, :allowed_task_types, nil)},
      {:custom, Keyword.get(opts, :custom, nil)}
    ]
  end

  defp passes_all?(candidate, gates) do
    Enum.all?(gates, &passes_gate?(candidate, &1))
  end

  defp passes_gate?(_c, {:compiled, false}), do: true

  defp passes_gate?(c, {:compiled, true}) do
    compiled = fetch_field(meta(c), "compiled")
    is_nil(compiled) or compiled == true
  end

  defp passes_gate?(_c, {:tests_pass, false}), do: true

  defp passes_gate?(c, {:tests_pass, true}) do
    tests_passed = fetch_field(meta(c), "tests_passed")
    is_nil(tests_passed) or tests_passed == true
  end

  defp passes_gate?(c, {:min_bytes, min}) do
    answer = answer_text(c)
    byte_size(answer) >= min
  end

  defp passes_gate?(_c, {:max_bytes, nil}), do: true

  defp passes_gate?(c, {:max_bytes, max}) do
    answer = answer_text(c)
    byte_size(answer) <= max
  end

  defp passes_gate?(_c, {:task_types, nil}), do: true

  defp passes_gate?(c, {:task_types, allowed}) do
    meta = meta(c)
    task = meta["task_type"] || meta[:task_type]
    task_atom = if is_binary(task), do: String.to_existing_atom(task), else: task
    task_atom in allowed
  rescue
    ArgumentError -> false
  end

  defp passes_gate?(_c, {:custom, nil}), do: true
  defp passes_gate?(c, {:custom, fun}), do: fun.(c)

  defp meta(%{"meta" => m}), do: m
  defp meta(%{meta: m}), do: m
  defp meta(_), do: %{}

  defp answer_text(c) do
    messages = c["messages"] || c[:messages] || []

    messages
    |> Enum.filter(&((&1["role"] || &1[:role]) == "assistant"))
    |> Enum.map_join("", &(&1["content"] || &1[:content] || ""))
  end

  # Use Map.fetch to correctly distinguish false from nil/absent.
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

  defp safe_rate(_, 0), do: 0.0
  defp safe_rate(n, total), do: Float.round(n / total * 100, 1)
end
