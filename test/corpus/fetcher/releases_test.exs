defmodule Corpus.Fetcher.ReleasesTest do
  use ExUnit.Case, async: true

  alias Corpus.{Manifest, ManifestEntry}
  alias Corpus.Fetcher.Releases

  @moduletag :tmp_dir

  defp stub_client(releases) do
    fn _url, _headers -> {:ok, releases} end
  end

  defp manifest_dir(dir), do: Path.join([dir, "elixir", "manifests"])

  describe "fetch_all/3 — happy path" do
    test "writes a release entry and returns {:ok, entry}", %{tmp_dir: dir} do
      releases = [
        %{"tag_name" => "v1.0.0", "body" => "Initial release", "published_at" => "2024-01-01"}
      ]

      {:ok, [{:ok, entry}]} =
        Releases.fetch_all(:elixir, [%{owner: "acme", repo: "mylib"}],
          data_dir: dir,
          client: stub_client(releases)
        )

      assert entry.source_kind == :changelog
      assert entry.reference =~ "v1.0.0"
      assert File.exists?(entry.local_path)
    end

    test "records entry in the manifest", %{tmp_dir: dir} do
      releases = [
        %{"tag_name" => "v2.0.0", "body" => "Big release", "published_at" => "2024-06-01"}
      ]

      Releases.fetch_all(:elixir, [%{owner: "acme", repo: "mylib"}],
        data_dir: dir,
        client: stub_client(releases)
      )

      assert Manifest.count(manifest_dir(dir)) == 1
    end
  end

  describe "fetch_all/3 — nil tag_name dedup" do
    test "nil tag_name release is stored with 'unknown' reference", %{tmp_dir: dir} do
      releases = [%{"tag_name" => nil, "body" => "Draft release", "published_at" => nil}]

      {:ok, [{:ok, entry}]} =
        Releases.fetch_all(:elixir, [%{owner: "acme", repo: "mylib"}],
          data_dir: dir,
          client: stub_client(releases)
        )

      assert entry.reference == "github:acme/mylib/releases/unknown"
    end

    test "nil tag_name release is skipped when 'unknown' reference already exists", %{
      tmp_dir: dir
    } do
      # Pre-seed the manifest with the 'unknown' reference so the dedup check fires
      existing_entry = %ManifestEntry{
        id: ManifestEntry.generate_id(:elixir, :changelog, "github:acme/mylib/releases/unknown"),
        domain: :elixir,
        source_kind: :changelog,
        reference: "github:acme/mylib/releases/unknown",
        fetched_at: DateTime.utc_now()
      }

      Manifest.append(manifest_dir(dir), existing_entry)

      releases = [%{"tag_name" => nil, "body" => "Draft", "published_at" => nil}]

      {:ok, results} =
        Releases.fetch_all(:elixir, [%{owner: "acme", repo: "mylib"}],
          data_dir: dir,
          client: stub_client(releases)
        )

      assert results == []
      assert Manifest.count(manifest_dir(dir)) == 1
    end

    test "tagged release is skipped when already in manifest", %{tmp_dir: dir} do
      releases = [%{"tag_name" => "v1.0.0", "body" => "Release", "published_at" => "2024-01-01"}]

      Releases.fetch_all(:elixir, [%{owner: "acme", repo: "mylib"}],
        data_dir: dir,
        client: stub_client(releases)
      )

      {:ok, results} =
        Releases.fetch_all(:elixir, [%{owner: "acme", repo: "mylib"}],
          data_dir: dir,
          client: stub_client(releases)
        )

      assert results == []
      assert Manifest.count(manifest_dir(dir)) == 1
    end
  end

  describe "fetch_all/3 — error handling" do
    test "client errors are returned as {:error, reason}", %{tmp_dir: dir} do
      failing = fn _url, _headers -> {:error, :timeout} end

      {:ok, results} =
        Releases.fetch_all(:elixir, [%{owner: "acme", repo: "mylib"}],
          data_dir: dir,
          client: failing
        )

      assert [{:error, {:releases_fetch, "acme/mylib", :timeout}}] = results
    end

    test "one failing spec does not prevent others", %{tmp_dir: dir} do
      call_count = :counters.new(1, [])

      client = fn _url, _headers ->
        :counters.add(call_count, 1, 1)

        if :counters.get(call_count, 1) == 1 do
          {:error, :refused}
        else
          {:ok, [%{"tag_name" => "v1.0.0", "body" => "ok", "published_at" => "2024-01-01"}]}
        end
      end

      specs = [%{owner: "bad", repo: "repo"}, %{owner: "good", repo: "repo"}]
      {:ok, results} = Releases.fetch_all(:elixir, specs, data_dir: dir, client: client)

      assert Enum.count(results, &match?({:error, _}, &1)) == 1
      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    end
  end
end
