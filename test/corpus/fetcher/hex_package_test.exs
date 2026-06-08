defmodule Corpus.Fetcher.HexPackageTest do
  use ExUnit.Case, async: true

  alias Corpus.Fetcher
  alias Corpus.Fetcher.HexPackage

  describe "search_json_path/4" do
    test "matches Corpus.Fetcher.raw_path for the same inputs" do
      assert HexPackage.search_json_path(:elixir, "ecto", nil, "data") ==
               Fetcher.raw_path(:elixir, :official_hex_docs, "ecto/search.json", "data")
    end

    test "matches raw_path when version is provided" do
      assert HexPackage.search_json_path(:elixir, "phoenix", "1.7.0", "data") ==
               Fetcher.raw_path(:elixir, :official_hex_docs, "phoenix/1.7.0/search.json", "data")
    end

    test "matches raw_path with a custom data_dir" do
      assert HexPackage.search_json_path(:my_domain, "broadway", nil, "/tmp/corpus") ==
               Fetcher.raw_path(
                 :my_domain,
                 :official_hex_docs,
                 "broadway/search.json",
                 "/tmp/corpus"
               )
    end

    test "sanitizes special characters in package name the same way raw_path does" do
      # Ensures the regex delegation is live — both functions apply the same transform
      assert HexPackage.search_json_path(:elixir, "some/weird:pkg", nil, "data") ==
               Fetcher.raw_path(:elixir, :official_hex_docs, "some/weird:pkg/search.json", "data")
    end
  end

  describe "module_targets/3" do
    test "returns empty list for nil body" do
      assert [] = HexPackage.module_targets("ecto", nil, "3.11.0")
    end

    test "returns targets for each module in the search index" do
      body =
        Jason.encode!(%{
          "items" => [
            %{"type" => "module", "title" => "Ecto.Query"},
            %{"type" => "module", "title" => "Ecto.Schema"},
            %{"type" => "function", "title" => "Ecto.Query.from/2"}
          ]
        })

      targets = HexPackage.module_targets("ecto", body, "3.11.0")
      assert length(targets) == 2
      assert Enum.all?(targets, &String.contains?(&1.reference, "ecto"))
    end

    test "returns empty list for unparseable body" do
      assert [] = HexPackage.module_targets("ecto", "not json", nil)
    end
  end
end
