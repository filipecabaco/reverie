defmodule Mix.Tasks.Reverie.Freeze do
  use Mix.Task

  @shortdoc "Freeze a dataset snapshot from generated candidates"

  @moduledoc """
  Reads generated candidates from JSONL, applies quality filters,
  deduplicates, splits into train/val/test/regression, and writes a
  frozen snapshot.

  ## Usage

      mix reverie.freeze --domain elixir --version v0.1

  ## Options

      --domain     Domain key. Default: elixir
      --version    Dataset version label. Default: v0.1
      --source     Source JSONL file. Default: data/<domain>/generated/candidates.jsonl
      --out        Snapshot directory. Default: data/<domain>/datasets/<version>
      --data-dir   Root data directory. Default: data
      --seed       Shuffle seed for reproducibility. Default: 42
  """

  @switches [
    domain: :string,
    version: :string,
    source: :string,
    out: :string,
    data_dir: :string,
    seed: :integer
  ]
  @defaults [domain: "elixir", version: "v0.1", data_dir: "data", seed: 42]

  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    opts = Keyword.merge(@defaults, opts)

    domain_str = opts[:domain]
    domain = Mix.Tasks.Reverie.Helpers.resolve_domain(domain_str)
    version = opts[:version]
    data_dir = opts[:data_dir]

    source = opts[:source] || Path.join([data_dir, domain_str, "generated", "candidates.jsonl"])
    snapshot_dir = opts[:out] || Path.join([data_dir, domain_str, "datasets", version])

    unless File.exists?(source) do
      Mix.raise("Source file not found: #{source}\nRun mix reverie.generate first.")
    end

    domain_cfg = Domains.Registry.config(domain)
    quality_opts = Map.get(domain_cfg, :quality, [])

    ratios =
      Map.get(domain_cfg, :split_ratios, %{
        train: 0.75,
        validation: 0.10,
        test: 0.10,
        regression: 0.05
      })

    Mix.shell().info("❄  Freezing dataset #{domain_str}-#{version}")
    Mix.shell().info("   Source: #{source}")
    Mix.shell().info("   Output: #{snapshot_dir}")

    case Ingest.DatasetBuilder.build(
           source_paths: [source],
           snapshot_dir: snapshot_dir,
           domain: domain,
           dataset_id: "#{domain_str}-#{version}",
           ratios: ratios,
           quality: quality_opts,
           seed: opts[:seed]
         ) do
      {:ok, result} ->
        Mix.shell().info("\n✓ Dataset frozen.")
        Mix.shell().info(Ingest.DistributionReport.summary(result.report))

        Mix.shell().info(
          "  Dedup removed: #{result.dedup_stats.dropped_as_duplicates} duplicates"
        )

        Mix.shell().info("  Quality dropped: #{result.quality_summary.dropped} candidates")

      {:error, reason} ->
        Mix.raise("Freeze failed: #{inspect(reason)}")
    end
  end
end
