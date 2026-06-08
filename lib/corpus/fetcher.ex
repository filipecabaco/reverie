defmodule Corpus.Fetcher do
  @moduledoc """
  Fetches source documents into the raw corpus with hash-based resumption.

  Takes a list of `{source_kind, target}` pairs where `target` is a map
  with at least `:reference` and `:url`. Already-fetched references (present
  in the manifest) are skipped. New items are fetched concurrently via
  `Task.async_stream`, written to disk, and appended to the manifest.

  The HTTP client is injectable for testing:

      Corpus.Fetcher.fetch_all(:elixir, sources,
        client: fn url -> {:ok, "stub body for \#{url}"} end
      )

  Broadway (step 10) will replace the `Task.async_stream` here once the
  pipeline needs batching, checkpointing, and external queue support.
  """

  alias Corpus.{Manifest, ManifestEntry, SourcePolicy}

  @default_concurrency 4

  @type target :: %{
          required(:reference) => String.t(),
          required(:url) => String.t(),
          optional(:metadata) => map()
        }
  @type source :: {ManifestEntry.source_kind(), target()}
  @type http_client :: (String.t() -> {:ok, binary()} | {:error, term()})

  @doc """
  Fetch a list of sources for a domain. Returns `{:ok, results}` where
  `results` is a list of `{:ok, entry}` or `{:error, reason}` per source.

  Options:
    - `:data_dir`     — root data directory (default `"data"`)
    - `:client`       — injectable HTTP client function (default: uses Req)
    - `:concurrency`  — max concurrent fetches (default: 4)
  """
  @spec fetch_all(atom(), [source()], keyword()) ::
          {:ok, [{:ok, ManifestEntry.t()} | {:error, term()}]}
  def fetch_all(domain, sources, opts \\ []) do
    data_dir = Keyword.get(opts, :data_dir, "data")
    concurrency = Keyword.get(opts, :concurrency, @default_concurrency)
    client = Keyword.get(opts, :client, &default_client/1)

    manifest_dir = manifest_dir(domain, data_dir)
    existing = Manifest.existing_references(manifest_dir)

    new_sources =
      Enum.reject(sources, fn {_kind, target} ->
        MapSet.member?(existing, target.reference)
      end)

    results =
      new_sources
      |> Task.async_stream(
        fn source -> fetch_one(domain, source, data_dir, manifest_dir, client) end,
        max_concurrency: concurrency,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, {:task_exit, reason}}
      end)

    {:ok, results}
  end

  @doc """
  Fetch a single source. Writes the file to disk and appends to the manifest.
  Returns `{:ok, ManifestEntry.t()}` or `{:error, reason}`.
  """
  @spec fetch_one(atom(), source(), Path.t(), Path.t(), http_client()) ::
          {:ok, ManifestEntry.t()} | {:error, term()}
  def fetch_one(domain, {source_kind, target}, data_dir, manifest_dir, client) do
    unless SourcePolicy.fetchable?(source_kind) do
      {:error, {:not_fetchable, source_kind}}
    else
      with {:ok, body} <- client.(target.url),
           {:ok, entry} <-
             write_and_record(domain, source_kind, target, body, data_dir, manifest_dir) do
        {:ok, entry}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp write_and_record(domain, source_kind, target, body, data_dir, manifest_dir) do
    content_hash = hash(body)
    local_path = raw_path(domain, source_kind, target.reference, data_dir)

    File.mkdir_p!(Path.dirname(local_path))
    File.write!(local_path, body)

    entry =
      %ManifestEntry{
        id: ManifestEntry.generate_id(domain, source_kind, target.reference),
        domain: domain,
        source_kind: source_kind,
        reference: target.reference,
        local_path: local_path,
        fetched_at: DateTime.utc_now(),
        content_hash: content_hash,
        version_context: get_in(target, [:metadata, :version]),
        notes: nil
      }
      |> SourcePolicy.apply_defaults()

    Manifest.append(manifest_dir, entry)
    {:ok, entry}
  end

  def raw_path(domain, source_kind, reference, data_dir) do
    filename = reference |> String.replace(~r"[^a-zA-Z0-9._-]", "_") |> String.slice(0, 200)
    Path.join([data_dir, to_string(domain), "raw", to_string(source_kind), filename])
  end

  defp manifest_dir(domain, data_dir) do
    Path.join([data_dir, to_string(domain), "manifests"])
  end

  defp hash(body) do
    :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
  end

  defp default_client(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %{status: 200, body: body}} -> {:ok, Jason.encode!(body)}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
