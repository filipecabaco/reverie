defmodule Corpus.Fetcher.HexPackage do
  @moduledoc """
  Builds fetch targets for individual HexDocs module documentation pages.

  Complements `Corpus.Fetcher.HexDocs`, which fetches only the search index
  and package index page. This module expands corpus coverage to every
  documented module by reading the already-fetched search index and returning
  one target per module page.

  Typical build-task flow:
  1. Fetch `search.json` with `Corpus.Fetcher.HexDocs.targets/2`
  2. Read the saved file, pass body to `module_targets/3`
  3. Fetch the returned targets with `Corpus.Fetcher.fetch_all/3`
  """

  alias Corpus.Fetcher.HexDocs

  @doc """
  Returns fetch targets for every module page listed in a package's search index.

  `search_json_body` should be the raw content of the already-fetched
  `search.json` file. Returns an empty list when the body is nil or unparseable.
  """
  @spec module_targets(String.t(), binary() | nil, String.t() | nil) :: [HexDocs.target()]
  def module_targets(_package, nil, _version), do: []

  def module_targets(package, search_json_body, version) do
    search_json_body
    |> HexDocs.extract_modules()
    |> Enum.map(&HexDocs.module_target(package, &1, version))
  end

  @doc """
  Returns the expected on-disk path for a package's `search.json` file.

  Uses the same sanitization logic as `Corpus.Fetcher` to reconstruct the
  local path without requiring a manifest lookup.
  """
  @spec search_json_path(atom(), String.t(), String.t() | nil, Path.t()) :: Path.t()
  def search_json_path(domain, package, version \\ nil, data_dir \\ "data") do
    base = if version, do: "#{package}/#{version}", else: package
    reference = "#{base}/search.json"
    Corpus.Fetcher.raw_path(domain, :official_hex_docs, reference, data_dir)
  end
end
