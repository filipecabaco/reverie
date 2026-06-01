defmodule Corpus.FetcherTest do
  use ExUnit.Case, async: true

  alias Corpus.{Fetcher, Manifest, ManifestEntry}

  @moduletag :tmp_dir

  describe "fetch_all/3 — happy path" do
    test "fetches new sources and writes manifest entries", %{tmp_dir: dir} do
      sources = [
        {:official_hex_docs,
         %{reference: "hexdocs/ecto/index.html", url: "https://example.com/ecto"}},
        {:official_hex_docs,
         %{reference: "hexdocs/phoenix/index.html", url: "https://example.com/phoenix"}}
      ]

      {:ok, results} = Fetcher.fetch_all(:elixir, sources, data_dir: dir, client: stub_client())

      assert length(results) == 2
      assert Enum.all?(results, &match?({:ok, %ManifestEntry{}}, &1))

      manifest_dir = Path.join([dir, "elixir", "manifests"])
      assert Manifest.count(manifest_dir) == 2
    end

    test "writes raw files to disk", %{tmp_dir: dir} do
      sources = [
        {:official_hex_docs, %{reference: "hexdocs/ecto", url: "https://example.com/ecto"}}
      ]

      Fetcher.fetch_all(:elixir, sources, data_dir: dir, client: stub_client("body content"))

      raw_files = Path.wildcard(Path.join([dir, "elixir", "raw", "**", "*"]))
      assert Enum.any?(raw_files, &File.regular?/1)
    end

    test "manifest entry has content_hash set", %{tmp_dir: dir} do
      sources = [
        {:official_hex_docs, %{reference: "hexdocs/ecto", url: "https://example.com/ecto"}}
      ]

      {:ok, [{:ok, entry}]} =
        Fetcher.fetch_all(:elixir, sources, data_dir: dir, client: stub_client())

      assert is_binary(entry.content_hash)
      assert String.length(entry.content_hash) == 64
    end

    test "entry domain and source_kind are set correctly", %{tmp_dir: dir} do
      sources = [
        {:changelog,
         %{reference: "github/phoenix/CHANGELOG.md", url: "https://example.com/changelog"}}
      ]

      {:ok, [{:ok, entry}]} =
        Fetcher.fetch_all(:elixir, sources, data_dir: dir, client: stub_client())

      assert entry.domain == :elixir
      assert entry.source_kind == :changelog
    end
  end

  describe "fetch_all/3 — resumption" do
    test "skips references already in the manifest", %{tmp_dir: dir} do
      sources = [
        {:official_hex_docs, %{reference: "hexdocs/ecto", url: "https://example.com/ecto"}}
      ]

      {:ok, _} = Fetcher.fetch_all(:elixir, sources, data_dir: dir, client: stub_client("first"))

      {:ok, results} =
        Fetcher.fetch_all(:elixir, sources, data_dir: dir, client: stub_client("second"))

      assert results == []

      manifest_dir = Path.join([dir, "elixir", "manifests"])
      assert Manifest.count(manifest_dir) == 1
    end

    test "fetches only new references in a second run", %{tmp_dir: dir} do
      first = [
        {:official_hex_docs, %{reference: "hexdocs/ecto", url: "https://example.com/ecto"}}
      ]

      second = [
        {:official_hex_docs, %{reference: "hexdocs/phoenix", url: "https://example.com/phoenix"}}
      ]

      {:ok, _} = Fetcher.fetch_all(:elixir, first, data_dir: dir, client: stub_client())

      {:ok, results} =
        Fetcher.fetch_all(:elixir, first ++ second, data_dir: dir, client: stub_client())

      assert length(results) == 1
      [{:ok, entry}] = results
      assert entry.reference == "hexdocs/phoenix"
    end
  end

  describe "fetch_all/3 — policy enforcement" do
    test "forum_content sources are not fetched", %{tmp_dir: dir} do
      sources = [
        {:forum_content, %{reference: "forum/post/123", url: "https://forum.example.com/123"}}
      ]

      {:ok, results} = Fetcher.fetch_all(:elixir, sources, data_dir: dir, client: stub_client())

      assert [{:error, {:not_fetchable, :forum_content}}] = results
    end

    test "source policy defaults are applied to entries", %{tmp_dir: dir} do
      sources = [
        {:github_issue, %{reference: "github/issues/1", url: "https://github.com/issues/1"}}
      ]

      {:ok, [{:ok, entry}]} =
        Fetcher.fetch_all(:elixir, sources, data_dir: dir, client: stub_client())

      assert entry.training_allowed == false
      assert entry.redistribution_allowed == false
    end
  end

  describe "fetch_all/3 — error handling" do
    test "HTTP errors are returned as {:error, reason}", %{tmp_dir: dir} do
      failing_client = fn _url -> {:error, :connection_refused} end

      sources = [
        {:official_hex_docs, %{reference: "hexdocs/ecto", url: "https://example.com/ecto"}}
      ]

      {:ok, results} = Fetcher.fetch_all(:elixir, sources, data_dir: dir, client: failing_client)
      assert [{:error, :connection_refused}] = results
    end

    test "one failure does not prevent other sources from being fetched", %{tmp_dir: dir} do
      call_count = :counters.new(1, [])

      client = fn _url ->
        :counters.add(call_count, 1, 1)
        n = :counters.get(call_count, 1)
        if n == 1, do: {:error, :timeout}, else: {:ok, "body"}
      end

      sources = [
        {:official_hex_docs, %{reference: "ref-1", url: "https://example.com/1"}},
        {:official_hex_docs, %{reference: "ref-2", url: "https://example.com/2"}}
      ]

      {:ok, results} = Fetcher.fetch_all(:elixir, sources, data_dir: dir, client: client)

      assert length(results) == 2
      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, _}, &1)) == 1
    end
  end

  defp stub_client(body \\ "<html>stub</html>") do
    fn _url -> {:ok, body} end
  end
end
