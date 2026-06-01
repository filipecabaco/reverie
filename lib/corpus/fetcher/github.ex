defmodule Corpus.Fetcher.GitHub do
  @moduledoc """
  Builds fetch targets for GitHub repositories.

  Fetches source files via the raw content URL, not the GitHub API,
  to avoid rate limits for large repositories.
  Only `.ex`, `.exs`, and `.md` files are targeted by default.
  """

  @raw_base "https://raw.githubusercontent.com"
  @api_base "https://api.github.com"

  @default_extensions ~w(.ex .exs .md)
  @default_branch "main"

  @type target :: %{reference: String.t(), url: String.t(), metadata: map()}

  @doc """
  Returns the API URL for fetching a repo's file tree.
  Pass the result body to `extract_targets/3` to get individual file targets.
  """
  @spec tree_url(String.t(), String.t(), String.t()) :: String.t()
  def tree_url(owner, repo, branch \\ @default_branch) do
    "#{@api_base}/repos/#{owner}/#{repo}/git/trees/#{branch}?recursive=1"
  end

  @doc """
  Parses a GitHub tree API response and returns fetch targets for matching files.
  """
  @spec extract_targets(binary(), String.t(), String.t(), keyword()) :: [target()]
  def extract_targets(tree_body, owner, repo, opts \\ []) do
    branch = Keyword.get(opts, :branch, @default_branch)
    extensions = Keyword.get(opts, :extensions, @default_extensions)
    max_size_bytes = Keyword.get(opts, :max_size_bytes, 100_000)

    case Jason.decode(tree_body) do
      {:ok, %{"tree" => files}} ->
        files
        |> Enum.filter(&file_matches?(&1, extensions, max_size_bytes))
        |> Enum.map(&build_target(&1, owner, repo, branch))

      _ ->
        []
    end
  end

  @doc "Returns the fetch target for a single known file path."
  @spec file_target(String.t(), String.t(), String.t(), String.t()) :: target()
  def file_target(owner, repo, path, branch \\ @default_branch) do
    reference = "github:#{owner}/#{repo}/#{branch}/#{path}"
    url = "#{@raw_base}/#{owner}/#{repo}/#{branch}/#{path}"

    %{
      reference: reference,
      url: url,
      metadata: %{owner: owner, repo: repo, branch: branch, path: path}
    }
  end

  @doc "Returns the fetch target for a repo's CHANGELOG or release notes."
  @spec changelog_target(String.t(), String.t(), String.t()) :: target()
  def changelog_target(owner, repo, branch \\ @default_branch) do
    file_target(owner, repo, "CHANGELOG.md", branch)
  end

  defp file_matches?(%{"type" => "blob", "path" => path, "size" => size}, extensions, max_bytes) do
    ext = Path.extname(path)
    ext in extensions and size <= max_bytes
  end

  defp file_matches?(_, _, _), do: false

  defp build_target(%{"path" => path}, owner, repo, branch) do
    file_target(owner, repo, path, branch)
  end
end
