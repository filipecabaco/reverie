defmodule Corpus.Fetcher.GitHubTest do
  use ExUnit.Case, async: true

  alias Corpus.Fetcher.GitHub

  describe "tree_url/3" do
    test "includes owner, repo, and branch" do
      url = GitHub.tree_url("elixir-lang", "elixir", "main")
      assert String.contains?(url, "elixir-lang")
      assert String.contains?(url, "elixir")
      assert String.contains?(url, "main")
      assert String.contains?(url, "recursive=1")
    end

    test "defaults to main branch" do
      url = GitHub.tree_url("owner", "repo")
      assert String.contains?(url, "main")
    end
  end

  describe "extract_targets/4" do
    test "returns targets only for matching extensions" do
      body =
        tree_body([
          %{"type" => "blob", "path" => "lib/foo.ex", "size" => 100},
          %{"type" => "blob", "path" => "lib/bar.js", "size" => 100},
          %{"type" => "blob", "path" => "README.md", "size" => 200}
        ])

      targets = GitHub.extract_targets(body, "owner", "repo")
      paths = Enum.map(targets, & &1.metadata.path)
      assert "lib/foo.ex" in paths
      assert "README.md" in paths
      refute "lib/bar.js" in paths
    end

    test "skips files exceeding max_size_bytes" do
      body =
        tree_body([
          %{"type" => "blob", "path" => "big.ex", "size" => 200_000},
          %{"type" => "blob", "path" => "small.ex", "size" => 500}
        ])

      targets = GitHub.extract_targets(body, "owner", "repo", max_size_bytes: 100_000)
      paths = Enum.map(targets, & &1.metadata.path)
      assert "small.ex" in paths
      refute "big.ex" in paths
    end

    test "skips tree entries (directories)" do
      body =
        tree_body([
          %{"type" => "tree", "path" => "lib", "size" => 0},
          %{"type" => "blob", "path" => "lib/foo.ex", "size" => 100}
        ])

      targets = GitHub.extract_targets(body, "owner", "repo")
      assert length(targets) == 1
    end

    test "returns empty list for invalid JSON" do
      assert [] = GitHub.extract_targets("not json", "owner", "repo")
    end

    test "each target has a raw.githubusercontent.com url" do
      body = tree_body([%{"type" => "blob", "path" => "lib/a.ex", "size" => 50}])
      [t] = GitHub.extract_targets(body, "owner", "repo")
      assert String.starts_with?(t.url, "https://raw.githubusercontent.com")
    end

    test "reference encodes owner/repo/branch/path" do
      body = tree_body([%{"type" => "blob", "path" => "lib/a.ex", "size" => 50}])
      [t] = GitHub.extract_targets(body, "elixir-lang", "elixir", branch: "main")
      assert String.contains?(t.reference, "elixir-lang")
      assert String.contains?(t.reference, "lib/a.ex")
    end
  end

  describe "file_target/4" do
    test "builds reference in github:owner/repo/branch/path format" do
      t = GitHub.file_target("elixir-lang", "elixir", "lib/elixir.ex")
      assert t.reference == "github:elixir-lang/elixir/main/lib/elixir.ex"
    end

    test "builds raw githubusercontent url" do
      t = GitHub.file_target("elixir-lang", "elixir", "lib/elixir.ex", "v1.18")
      assert t.url == "https://raw.githubusercontent.com/elixir-lang/elixir/v1.18/lib/elixir.ex"
    end
  end

  describe "changelog_target/3" do
    test "targets CHANGELOG.md" do
      t = GitHub.changelog_target("phoenixframework", "phoenix")
      assert String.ends_with?(t.reference, "CHANGELOG.md")
    end
  end

  defp tree_body(files) do
    Jason.encode!(%{"tree" => files})
  end
end
