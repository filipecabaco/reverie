defmodule Mix.Tasks.Reverie.Status do
  use Mix.Task

  @shortdoc "Show pipeline status for a domain"

  @moduledoc """
  Shows what exists on disk for a domain: corpus, candidates,
  frozen datasets, and artifacts.

  ## Usage

      mix reverie.status
      mix reverie.status --domain postgres

  ## Options

      --domain    Domain key, or "all" for every domain. Default: all
      --data-dir  Root data directory. Default: data
  """

  @switches [domain: :string, data_dir: :string]
  @defaults [domain: "all", data_dir: "data"]

  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    opts = Keyword.merge(@defaults, opts)

    data_dir = opts[:data_dir]

    domains =
      case opts[:domain] do
        "all" -> Domains.Registry.domains()
        d -> [Mix.Tasks.Reverie.Helpers.resolve_domain(d)]
      end

    for domain <- Enum.sort(domains) do
      print_domain_status(domain, data_dir)
    end
  end

  defp print_domain_status(domain, data_dir) do
    domain_str = to_string(domain)
    base = Path.join(data_dir, domain_str)

    Mix.shell().info("\n#{String.upcase(domain_str)}")
    Mix.shell().info(String.duplicate("─", 40))

    # Corpus DB
    corpus = Path.join(base, "corpus.db")
    print_file("Corpus DB", corpus)

    # Manifests
    manifest = Path.join([base, "manifests", "raw.jsonl"])

    count =
      if File.exists?(manifest), do: Corpus.Manifest.count(Path.join(base, "manifests")), else: 0

    print_line("Manifests", format_count(count, "item"))

    # Briefs (from corpus DB if it exists)
    brief_count =
      if File.exists?(corpus) do
        case Corpus.Store.open_readonly(domain, data_dir) do
          {:ok, conn} ->
            {:ok, briefs} = Corpus.Store.list_briefs(conn)
            Corpus.Store.close(conn)
            length(briefs)

          _ ->
            0
        end
      else
        0
      end

    print_line("Briefs", format_count(brief_count, "brief"))

    # Generated candidates
    candidates_file = Path.join([base, "generated", "candidates.jsonl"])

    candidate_count =
      if File.exists?(candidates_file), do: DatasetGen.Output.count(candidates_file), else: 0

    print_line("Candidates", format_count(candidate_count, "candidate"))

    # Frozen datasets
    datasets_dir = Path.join(base, "datasets")

    if File.dir?(datasets_dir) do
      versions = File.ls!(datasets_dir) |> Enum.sort()

      if versions == [] do
        print_line("Datasets", "none")
      else
        for v <- versions do
          snap_dir = Path.join(datasets_dir, v)
          train_count = Ingest.Snapshot.count(snap_dir, :train)
          test_count = Ingest.Snapshot.count(snap_dir, :test)
          print_line("Dataset #{v}", "train=#{train_count} test=#{test_count}")
        end
      end
    else
      print_line("Datasets", "none")
    end

    # Selected model
    model_file = Path.join(data_dir, "selected_model.json")

    if File.exists?(model_file) do
      {:ok, m} = Train.Bakeoff.load_selection(data_dir)
      print_line("Selected model", m["id"] || "unknown")
    else
      print_line("Selected model", "not chosen yet")
    end
  end

  defp print_file(label, path) do
    status = if File.exists?(path), do: "✓  #{path}", else: "–  (not created)"
    print_line(label, status)
  end

  defp print_line(label, value) do
    Mix.shell().info("  #{String.pad_trailing(label, 16)} #{value}")
  end

  defp format_count(0, unit), do: "no #{unit}s"
  defp format_count(1, unit), do: "1 #{unit}"
  defp format_count(n, unit), do: "#{n} #{unit}s"
end
