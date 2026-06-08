defmodule Mix.Tasks.Reverie.Corpus.Build do
  use Mix.Task

  @shortdoc "Build the knowledge-base corpus for a domain (fetch + index)"

  @moduledoc """
  Fetches raw materials for a domain — official docs, example repositories,
  and release notes — then chunks and indexes them into the corpus store so
  they are available for retrieval-augmented generation and brief research.

  Sources are declared in the domain module's `sources/0` callback.

  ## Two phases

      fetch — download raw sources and record in the manifest
      index — chunk manifest entries and insert into corpus.db

  Both phases run by default. Use `--phase` to run only one.

  ## What gets fetched

    - HexDocs search index + every documented module page
    - GitHub repository source files (.ex, .exs, .md) via the tree API
    - GitHub release notes via the Releases API

  ## Usage

      mix reverie.corpus.build --domain <domain>
      mix reverie.corpus.build --domain <domain> --phase fetch --github-token ghp_xxx
      mix reverie.corpus.build --domain <domain> --phase index --force
      mix reverie.corpus.build --domain <domain> --concurrency 8

  ## Options

      --domain        Domain key. Required.
      --phase         fetch, index, or both (default: both)
      --github-token  GitHub personal access token (recommended; raises rate limit
                      from 60 to 5 000 API requests/hour)
      --concurrency   Parallel HTTP fetches. Default: 4
      --data-dir      Root data directory. Default: data
      --force         Re-index already-indexed entries (index phase only)
  """

  alias Corpus.{Fetcher, Indexer}
  alias Corpus.Fetcher.{GitHub, HexDocs, HexPackage, Releases}

  @switches [
    domain: :string,
    phase: :string,
    github_token: :string,
    concurrency: :integer,
    data_dir: :string,
    force: :boolean
  ]

  @defaults [phase: "both", data_dir: "data", concurrency: 4, force: false]

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    opts = Keyword.merge(@defaults, opts)

    unless opts[:domain], do: Mix.raise("--domain is required. Run `mix reverie.domain` to see available domains.")

    domain_str = opts[:domain]
    phase = opts[:phase]
    token = opts[:github_token]
    concurrency = opts[:concurrency]
    data_dir = opts[:data_dir]
    force = opts[:force]

    domain = Mix.Tasks.Reverie.Helpers.resolve_domain(domain_str)
    domain_mod = Domains.Registry.module_for(domain)

    unless function_exported?(domain_mod, :sources, 0) do
      Mix.raise(
        "#{inspect(domain_mod)} has no sources/0 defined. " <>
          "Add a sources/0 implementation to configure which packages, " <>
          "repos, and release histories to fetch."
      )
    end

    sources = domain_mod.sources()

    if phase in ["fetch", "both"] do
      run_fetch(domain, sources, token, concurrency, data_dir)
    end

    if phase in ["index", "both"] do
      run_index(domain, data_dir, force)
    end
  end

  # ---------------------------------------------------------------------------
  # Fetch phase
  # ---------------------------------------------------------------------------

  defp run_fetch(domain, sources, token, concurrency, data_dir) do
    Mix.shell().info("\n=== Fetch phase ===")

    fetch_opts = [data_dir: data_dir, concurrency: concurrency]
    github_opts = Keyword.put(fetch_opts, :github_token, token)
    api_headers = github_api_headers(token)

    hex_packages = Map.get(sources, :hex_packages, [])
    repos = Map.get(sources, :repos, [])
    releases = Map.get(sources, :releases, [])

    if hex_packages != [] do
      Mix.shell().info("\n-- HexDocs packages (#{length(hex_packages)}) --")
      fetch_hex_packages(domain, hex_packages, fetch_opts)
    end

    if repos != [] do
      Mix.shell().info("\n-- GitHub repos (#{length(repos)}) --")
      fetch_repos(domain, repos, api_headers, fetch_opts)
    end

    if releases != [] do
      Mix.shell().info("\n-- GitHub release notes (#{length(releases)} repos) --")
      fetch_releases(domain, releases, github_opts)
    end
  end

  defp fetch_hex_packages(domain, packages, opts) do
    Enum.each(packages, fn spec ->
      package = spec.package
      version = Map.get(spec, :version)

      # Phase 1: search index + package index page
      index_targets =
        HexDocs.targets(package, version)
        |> Enum.map(&{:official_hex_docs, &1})

      {:ok, results} = Fetcher.fetch_all(domain, index_targets, opts)
      new_count = Enum.count(results, &match?({:ok, _}, &1))
      Mix.shell().info("  #{package}: index (#{new_count} new)")

      # Phase 2: per-module pages expanded from the search index
      search_path = HexPackage.search_json_path(domain, package, version, opts[:data_dir])

      module_targets =
        case File.read(search_path) do
          {:ok, body} ->
            HexPackage.module_targets(package, body, version)
            |> Enum.map(&{:official_hex_docs, &1})

          _ ->
            []
        end

      if module_targets != [] do
        {:ok, mod_results} = Fetcher.fetch_all(domain, module_targets, opts)
        mod_new = Enum.count(mod_results, &match?({:ok, _}, &1))
        Mix.shell().info("  #{package}: #{length(module_targets)} modules (#{mod_new} new)")
      end
    end)
  end

  defp fetch_repos(domain, repos, api_headers, opts) do
    Enum.each(repos, fn spec ->
      owner = spec.owner
      repo = spec.repo
      branch = Map.get(spec, :branch, "main")

      tree_url = GitHub.tree_url(owner, repo, branch)

      case Req.get(tree_url, headers: api_headers) do
        {:ok, %{status: 200, body: body}} ->
          body_bin = if is_binary(body), do: body, else: Jason.encode!(body)
          targets = GitHub.extract_targets(body_bin, owner, repo, branch: branch)
          wrapped = Enum.map(targets, &{:permissive_repo, &1})

          {:ok, results} = Fetcher.fetch_all(domain, wrapped, opts)
          new_count = Enum.count(results, &match?({:ok, _}, &1))
          Mix.shell().info("  #{owner}/#{repo}: #{length(targets)} files (#{new_count} new)")

        {:ok, %{status: 404}} ->
          Mix.shell().error("  #{owner}/#{repo}: not found (404)")

        {:ok, %{status: status}} ->
          Mix.shell().error("  #{owner}/#{repo}: HTTP #{status}")

        {:error, reason} ->
          Mix.shell().error("  #{owner}/#{repo}: #{inspect(reason)}")
      end
    end)
  end

  defp fetch_releases(domain, release_specs, opts) do
    {:ok, results} = Releases.fetch_all(domain, release_specs, opts)

    ok = Enum.count(results, &match?({:ok, _}, &1))
    errors = Enum.count(results, &match?({:error, _}, &1))

    Mix.shell().info("  #{ok} release notes written, #{errors} errors")

    Enum.each(results, fn
      {:error, {:releases_fetch, repo, {:http_status, 403}}} ->
        Mix.shell().error("  Rate limited for #{repo}. Pass --github-token to increase the limit.")

      {:error, {:releases_fetch, repo, reason}} ->
        Mix.shell().error("  #{repo}: #{inspect(reason)}")

      _ ->
        :ok
    end)
  end

  # ---------------------------------------------------------------------------
  # Index phase
  # ---------------------------------------------------------------------------

  defp run_index(domain, data_dir, force) do
    Mix.shell().info("\n=== Index phase ===")

    case Indexer.index_domain(domain, data_dir: data_dir, force: force) do
      {:ok, %{indexed: indexed, skipped: skipped, errors: errors}} ->
        Mix.shell().info(
          "  Indexed #{indexed} entries, skipped #{skipped} already-indexed, #{errors} errors"
        )

      {:error, reason} ->
        Mix.raise("Index failed: #{inspect(reason)}")
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp github_api_headers(nil), do: [{"accept", "application/vnd.github+json"}]

  defp github_api_headers(token),
    do: [{"accept", "application/vnd.github+json"}, {"authorization", "Bearer #{token}"}]
end
