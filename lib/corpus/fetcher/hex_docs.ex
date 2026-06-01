defmodule Corpus.Fetcher.HexDocs do
  @moduledoc """
  Builds fetch targets for Hex.pm package documentation.

  Returns a list of `{reference, url}` pairs. The reference is the
  canonical identifier stored in the manifest; the URL is what gets fetched.
  """

  @base_url "https://hexdocs.pm"

  @type target :: %{reference: String.t(), url: String.t(), metadata: map()}

  @doc """
  Returns fetch targets for a package's documentation.

  Targets:
    - The search index (JSON, lists all documented modules and functions)
    - The package top-level page (HTML)
  """
  @spec targets(String.t(), String.t() | nil) :: [target()]
  def targets(package, version \\ nil) do
    base = package_base(package, version)

    [
      %{
        reference: "#{base}/search.json",
        url: "#{@base_url}/#{base}/search.json",
        metadata: %{package: package, version: version, kind: :search_index}
      },
      %{
        reference: "#{base}/index.html",
        url: "#{@base_url}/#{base}/index.html",
        metadata: %{package: package, version: version, kind: :index}
      }
    ]
  end

  @doc "Returns the fetch target for a specific module's documentation page."
  @spec module_target(String.t(), String.t(), String.t() | nil) :: target()
  def module_target(package, module_name, version \\ nil) do
    base = package_base(package, version)
    slug = module_slug(module_name)

    %{
      reference: "#{base}/#{slug}.html",
      url: "#{@base_url}/#{base}/#{slug}.html",
      metadata: %{package: package, module: module_name, version: version, kind: :module_page}
    }
  end

  @doc "Extracts module names from a parsed search index body."
  @spec extract_modules(binary()) :: [String.t()]
  def extract_modules(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"items" => items}} ->
        items
        |> Enum.filter(&(&1["type"] == "module"))
        |> Enum.map(& &1["title"])
        |> Enum.uniq()

      _ ->
        []
    end
  end

  defp package_base(package, nil), do: package
  defp package_base(package, version), do: "#{package}/#{version}"

  defp module_slug(module_name) do
    module_name
    |> String.replace(".", "_")
    |> Macro.underscore()
    |> String.replace("__", "_")
  end
end
