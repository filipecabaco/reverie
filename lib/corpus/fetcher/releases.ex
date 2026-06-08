defmodule Corpus.Fetcher.Releases do
  @moduledoc """
  Fetches GitHub release notes and stores them as `:changelog` manifest entries.

  Uses the GitHub Releases API (`/repos/{owner}/{repo}/releases`). Each release
  body is saved as a Markdown file and recorded in the manifest. Existing
  references are skipped (hash-based resumption matches `Corpus.Fetcher`).

  Accepts an optional GitHub token for higher API rate limits (60 req/hr
  unauthenticated vs 5 000 req/hr with a token).
  """

  alias Corpus.{Manifest, ManifestEntry, SourcePolicy}

  @api_base "https://api.github.com"

  @type spec :: %{
          owner: String.t(),
          repo: String.t(),
          optional(:max_releases) => pos_integer()
        }

  @doc """
  Fetch release notes for every spec and write them as `:changelog` manifest
  entries. Returns `{:ok, results}` where each element is `{:ok, entry}` or
  `{:error, reason}`.

  Options:
    - `:data_dir`      — root data directory (default `"data"`)
    - `:github_token`  — bearer token for the GitHub API
  """
  @spec fetch_all(atom(), [spec()], keyword()) ::
          {:ok, [{:ok, ManifestEntry.t()} | {:error, term()}]}
  def fetch_all(domain, specs, opts \\ []) do
    data_dir = Keyword.get(opts, :data_dir, "data")
    token = Keyword.get(opts, :github_token)

    manifest_dir = Path.join([data_dir, to_string(domain), "manifests"])
    existing = Manifest.existing_references(manifest_dir)

    results =
      Enum.flat_map(specs, fn spec ->
        max = Map.get(spec, :max_releases, 20)

        case fetch_releases(spec.owner, spec.repo, max, token) do
          {:ok, releases} ->
            releases
            |> Enum.reject(fn rel ->
              MapSet.member?(existing, release_reference(spec.owner, spec.repo, rel["tag_name"]))
            end)
            |> Enum.map(&write_release(domain, spec.owner, spec.repo, &1, data_dir, manifest_dir))

          {:error, reason} ->
            [{:error, {:releases_fetch, "#{spec.owner}/#{spec.repo}", reason}}]
        end
      end)

    {:ok, results}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp fetch_releases(owner, repo, max, token) do
    url = "#{@api_base}/repos/#{owner}/#{repo}/releases?per_page=#{max}"

    case Req.get(url, headers: github_headers(token)) do
      {:ok, %{status: 200, body: releases}} when is_list(releases) ->
        {:ok, releases}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        Jason.decode(body)

      {:ok, %{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_release(domain, owner, repo, release, data_dir, manifest_dir) do
    tag = release["tag_name"] || "unknown"
    published = release["published_at"] || ""
    body = release["body"] || ""

    content = "# #{owner}/#{repo} — Release #{tag}\n\nPublished: #{published}\n\n#{body}"
    reference = release_reference(owner, repo, tag)
    local_path = release_path(domain, owner, repo, tag, data_dir)

    File.mkdir_p!(Path.dirname(local_path))
    File.write!(local_path, content)

    content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    entry =
      %ManifestEntry{
        id: ManifestEntry.generate_id(domain, :changelog, reference),
        domain: domain,
        source_kind: :changelog,
        reference: reference,
        local_path: local_path,
        fetched_at: DateTime.utc_now(),
        content_hash: content_hash,
        version_context: tag
      }
      |> SourcePolicy.apply_defaults()

    Manifest.append(manifest_dir, entry)
    {:ok, entry}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp release_reference(owner, repo, tag), do: "github:#{owner}/#{repo}/releases/#{tag}"

  defp release_path(domain, owner, repo, tag, data_dir) do
    safe_tag = String.replace(tag, ~r/[^a-zA-Z0-9._-]/, "_")
    Path.join([data_dir, to_string(domain), "raw", "changelog", "#{owner}_#{repo}_#{safe_tag}.md"])
  end

  defp github_headers(nil), do: [{"accept", "application/vnd.github+json"}]

  defp github_headers(token),
    do: [{"accept", "application/vnd.github+json"}, {"authorization", "Bearer #{token}"}]
end
