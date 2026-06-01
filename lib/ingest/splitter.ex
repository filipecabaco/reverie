defmodule Ingest.Splitter do
  @moduledoc """
  Splits a deduplicated candidate list into train/validation/test/regression
  splits while preserving brief-group integrity (§9.4).

  Brief grouping: all candidates sharing the same `brief_id` are assigned
  to the same split, so the model cannot see brief content in training and
  then be tested on examples grounded in that brief. Candidates with
  `brief_id: nil` are treated as independent and distributed freely.

  Ratios are configurable per domain. They are normalised to sum to 1.0
  and then applied to brief-groups first, with ungrouped candidates filling
  the remainder proportionally.

  Deduplication: two passes before splitting —
    1. Canonical instruction hash (lowercased, whitespace-collapsed)
    2. Canonical code hash (whitespace-collapsed)
  The first occurrence in the input list wins; duplicates are dropped.

  Split atoms: :train, :validation, :test, :regression
  """

  @default_ratios %{train: 0.75, validation: 0.10, test: 0.10, regression: 0.05}

  @type candidate :: map()
  @type split_name :: :train | :validation | :test | :regression
  @type splits :: %{split_name() => [candidate()]}

  @doc """
  Dedup and split `candidates` into named splits.
  Returns `{:ok, splits, dedup_stats}`.
  """
  @spec split([candidate()], map(), keyword()) :: {:ok, splits(), map()}
  def split(candidates, ratios \\ @default_ratios, opts \\ []) do
    seed = Keyword.get(opts, :seed, 42)
    normalised = normalise_ratios(ratios)

    {deduped, dedup_stats} = dedup(candidates)
    splits = assign_splits(deduped, normalised, seed)

    {:ok, splits, dedup_stats}
  end

  @doc "Default split ratios."
  @spec default_ratios() :: map()
  def default_ratios, do: @default_ratios

  # ---------------------------------------------------------------------------
  # Deduplication
  # ---------------------------------------------------------------------------

  defp dedup(candidates) do
    {kept, _seen_instruction, _seen_code, dropped} =
      Enum.reduce(candidates, {[], MapSet.new(), MapSet.new(), 0}, fn c, {acc, si, sc, dropped} ->
        ih = instruction_hash(c)
        ch = code_hash(c)

        if MapSet.member?(si, ih) or (ch != nil and MapSet.member?(sc, ch)) do
          {acc, si, sc, dropped + 1}
        else
          {[c | acc], MapSet.put(si, ih), maybe_put(sc, ch), dropped}
        end
      end)

    stats = %{
      before: length(candidates),
      after: length(kept),
      dropped_as_duplicates: dropped
    }

    {Enum.reverse(kept), stats}
  end

  defp instruction_hash(c) do
    text =
      (c["messages"] || c[:messages] || [])
      |> Enum.filter(&((&1["role"] || &1[:role]) == "user"))
      |> Enum.map_join("", &(&1["content"] || &1[:content] || ""))
      |> String.downcase()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
  end

  defp code_hash(c) do
    meta = c["meta"] || c[:meta] || %{}
    code = meta["code"] || meta[:code]

    if is_binary(code) and String.trim(code) != "" do
      normalised = code |> String.replace(~r/\s+/, " ") |> String.trim()
      :crypto.hash(:sha256, normalised) |> Base.encode16(case: :lower)
    else
      nil
    end
  end

  defp maybe_put(set, nil), do: set
  defp maybe_put(set, val), do: MapSet.put(set, val)

  # ---------------------------------------------------------------------------
  # Splitting with brief-group integrity
  # ---------------------------------------------------------------------------

  defp assign_splits(candidates, ratios, seed) do
    {briefed, ungrouped} = partition_by_brief(candidates)

    brief_groups = briefed |> Enum.group_by(&brief_id/1) |> Map.values()
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})
    shuffled_groups = Enum.shuffle(brief_groups)
    shuffled_ungrouped = Enum.shuffle(ungrouped)

    all_groups = shuffled_groups ++ Enum.map(shuffled_ungrouped, &[&1])
    total = length(all_groups)
    split_names = [:train, :validation, :test, :regression]

    {assignments, _} =
      split_names
      |> Enum.zip(counts_from_ratios(ratios, total, split_names))
      |> Enum.reduce({%{}, all_groups}, fn {split, count}, {acc, remaining} ->
        {taken, rest} = Enum.split(remaining, count)
        candidates_for_split = Enum.flat_map(taken, & &1)
        {Map.put(acc, split, candidates_for_split), rest}
      end)

    Map.new(split_names, fn name ->
      {name, Map.get(assignments, name, [])}
    end)
  end

  defp partition_by_brief(candidates) do
    Enum.split_with(candidates, fn c ->
      meta = c["meta"] || c[:meta] || %{}
      id = meta["brief_id"] || meta[:brief_id]
      not is_nil(id)
    end)
  end

  defp brief_id(c) do
    meta = c["meta"] || c[:meta] || %{}
    meta["brief_id"] || meta[:brief_id]
  end

  defp counts_from_ratios(ratios, total, split_names) do
    raw = Enum.map(split_names, fn name -> round(Map.get(ratios, name, 0.0) * total) end)
    assigned = Enum.sum(raw)

    if assigned < total do
      # Give leftover groups to train
      List.update_at(raw, 0, &(&1 + (total - assigned)))
    else
      raw
    end
  end

  defp normalise_ratios(ratios) do
    total = Enum.sum(Map.values(ratios))
    if total == 0, do: @default_ratios, else: Map.new(ratios, fn {k, v} -> {k, v / total} end)
  end
end
