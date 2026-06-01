defmodule Ingest.DatasetBuilder do
  @moduledoc """
  Domain-agnostic dataset freezer (§11).

  Reads generated candidates from one or more output files, applies quality
  gates, deduplicates, splits by brief-group integrity, writes frozen JSONL
  splits, and returns a distribution report.

  Everything is configurable — ratios, quality filters, seed — so the same
  code produces the Elixir dataset, the Postgres dataset, or any future domain
  without modification.

  Usage:

      {:ok, result} = Ingest.DatasetBuilder.build(
        source_paths: ["data/elixir/generated/run1.jsonl"],
        snapshot_dir: "data/elixir/datasets/v0.1",
        domain: :elixir,
        dataset_id: "elixir-v0.1",
        ratios: %{train: 0.75, validation: 0.10, test: 0.10, regression: 0.05},
        quality: [require_compiled: true, min_answer_bytes: 50],
        seed: 42
      )

      IO.puts(Ingest.DistributionReport.summary(result.report))
  """

  alias DatasetGen.Output
  alias Ingest.{DistributionReport, QualityFilter, Snapshot, Splitter}

  @type result :: %{
          snapshot_dir: Path.t(),
          meta: map(),
          report: DistributionReport.t(),
          quality_summary: map(),
          dedup_stats: map()
        }

  @doc """
  Build and freeze a dataset snapshot.

  Required opts:
    :source_paths  — list of JSONL files produced by the generation pipeline
    :snapshot_dir  — directory to write frozen splits into
    :domain        — atom domain name (used in metadata)
    :dataset_id    — string version identifier (e.g. "elixir-v0.1")

  Optional opts:
    :ratios        — split ratios map (default: 75/10/10/5)
    :quality       — opts passed to QualityFilter.filter/2
    :seed          — integer seed for shuffle reproducibility (default: 42)
    :base_model_candidate — model ID being evaluated against this dataset
    :tokenizer_id  — tokenizer used during ingest
    :source_manifest_hash — hash of the raw corpus manifest
    :brief_manifest_hash  — hash of the brief manifest
    :generation_config_hash — hash of the generation config used
  """
  @spec build(keyword()) :: {:ok, result()} | {:error, term()}
  def build(opts) do
    source_paths = Keyword.fetch!(opts, :source_paths)
    snapshot_dir = Keyword.fetch!(opts, :snapshot_dir)
    domain = Keyword.fetch!(opts, :domain)
    dataset_id = Keyword.fetch!(opts, :dataset_id)

    ratios = Keyword.get(opts, :ratios, Splitter.default_ratios())
    quality_opts = Keyword.get(opts, :quality, [])
    seed = Keyword.get(opts, :seed, 42)

    with {:ok, raw} <- load_candidates(source_paths),
         {:ok, filtered, quality_summary} <- QualityFilter.filter(raw, quality_opts),
         {:ok, splits, dedup_stats} <- Splitter.split(filtered, ratios, seed: seed),
         {:ok, meta} <- freeze(snapshot_dir, splits, dataset_id, domain, opts) do
      report = DistributionReport.compute(splits)

      {:ok,
       %{
         snapshot_dir: snapshot_dir,
         meta: meta,
         report: report,
         quality_summary: quality_summary,
         dedup_stats: dedup_stats
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp load_candidates(paths) do
    candidates =
      paths
      |> Enum.flat_map(&Output.read_all/1)
      |> Enum.to_list()

    {:ok, candidates}
  rescue
    e -> {:error, {:load_failed, Exception.message(e)}}
  end

  defp freeze(snapshot_dir, splits, dataset_id, domain, opts) do
    # Convert string-keyed JSON maps to the atom-keyed training_record format
    normalised =
      Map.new(splits, fn {split, candidates} ->
        records = Enum.map(candidates, &normalise_record/1)
        {split, records}
      end)

    meta_fields = %{
      dataset_id: dataset_id,
      domain: domain,
      base_model_candidate: opts[:base_model_candidate],
      tokenizer_id: opts[:tokenizer_id],
      source_manifest_hash: opts[:source_manifest_hash],
      brief_manifest_hash: opts[:brief_manifest_hash],
      generation_config_hash: opts[:generation_config_hash]
    }

    Snapshot.freeze(snapshot_dir, normalised, meta_fields)
  end

  defp normalise_record(candidate) do
    messages =
      (candidate["messages"] || candidate[:messages] || [])
      |> Enum.map(fn m ->
        %{
          role: m["role"] || m[:role],
          content: m["content"] || m[:content]
        }
      end)

    meta =
      candidate["meta"] || candidate[:meta] || %{}

    %{messages: messages, meta: meta}
  end
end
