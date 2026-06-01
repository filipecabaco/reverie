defmodule Corpus.Fetcher.HexDocsTest do
  use ExUnit.Case, async: true

  alias Corpus.Fetcher.HexDocs

  describe "targets/2" do
    test "returns search index and index page targets" do
      targets = HexDocs.targets("ecto")
      assert length(targets) == 2
      refs = Enum.map(targets, & &1.reference)
      assert Enum.any?(refs, &String.ends_with?(&1, "search.json"))
      assert Enum.any?(refs, &String.ends_with?(&1, "index.html"))
    end

    test "includes the package name in reference and url" do
      for t <- HexDocs.targets("phoenix") do
        assert String.contains?(t.reference, "phoenix")
        assert String.contains?(t.url, "phoenix")
      end
    end

    test "includes version in reference when provided" do
      targets = HexDocs.targets("ecto", "3.11.0")

      for t <- targets do
        assert String.contains?(t.reference, "3.11.0")
        assert String.contains?(t.url, "3.11.0")
      end
    end

    test "omits version segment when nil" do
      [t | _] = HexDocs.targets("ecto", nil)
      refute String.contains?(t.reference, "nil")
    end

    test "all targets have metadata with package key" do
      for t <- HexDocs.targets("broadway") do
        assert t.metadata.package == "broadway"
      end
    end
  end

  describe "module_target/3" do
    test "returns a target with module name in reference" do
      t = HexDocs.module_target("ecto", "Ecto.Query")
      assert String.contains?(t.reference, "ecto")
      assert t.metadata.module == "Ecto.Query"
    end

    test "url points to hexdocs.pm" do
      t = HexDocs.module_target("phoenix", "Phoenix.Router")
      assert String.starts_with?(t.url, "https://hexdocs.pm")
    end
  end

  describe "extract_modules/1" do
    test "extracts module titles from a valid search index" do
      body =
        Jason.encode!(%{
          "items" => [
            %{"type" => "module", "title" => "Ecto.Query"},
            %{"type" => "function", "title" => "Ecto.Query.from/2"},
            %{"type" => "module", "title" => "Ecto.Schema"}
          ]
        })

      assert ["Ecto.Query", "Ecto.Schema"] = HexDocs.extract_modules(body)
    end

    test "returns empty list for unparseable body" do
      assert [] = HexDocs.extract_modules("not json")
    end

    test "returns empty list when items key is missing" do
      assert [] = HexDocs.extract_modules(Jason.encode!(%{"other" => "data"}))
    end
  end
end
