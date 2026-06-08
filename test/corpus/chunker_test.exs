defmodule Corpus.ChunkerTest do
  use ExUnit.Case, async: true

  alias Corpus.Chunker

  describe "chunk/2 — hex_search_json" do
    test "parses items-keyed JSON object" do
      body =
        Jason.encode!(%{
          "items" => [
            %{"title" => "GenServer.call/3", "doc" => String.duplicate("x", 100)},
            %{"title" => "GenServer.cast/2", "doc" => String.duplicate("y", 100)}
          ]
        })

      chunks = Chunker.chunk(body, "elixir/search.json")
      assert length(chunks) == 2
      assert hd(chunks).metadata.kind == :function_doc
    end

    test "parses root-array JSON without raising" do
      body =
        Jason.encode!([
          %{"title" => "Enum.map/2", "doc" => String.duplicate("z", 100)},
          %{"title" => "Enum.filter/2", "doc" => String.duplicate("w", 100)}
        ])

      chunks = Chunker.chunk(body, "elixir/search.json")
      assert length(chunks) == 2
      assert Enum.all?(chunks, &(&1.metadata.kind == :function_doc))
    end

    test "root-array items carry correct titles" do
      body =
        Jason.encode!([
          %{"title" => "MyMod.fun/1", "doc" => String.duplicate("a", 100)}
        ])

      [chunk] = Chunker.chunk(body, "some/package/search.json")
      assert chunk.text =~ "MyMod.fun/1"
    end

    test "skips items whose doc is shorter than the minimum" do
      body =
        Jason.encode!(%{
          "items" => [
            %{"title" => "Short.fun/0", "doc" => "too short"},
            %{"title" => "Long.fun/0", "doc" => String.duplicate("a", 100)}
          ]
        })

      chunks = Chunker.chunk(body, "search.json")
      assert length(chunks) == 1
      assert hd(chunks).text =~ "Long.fun/0"
    end

    test "returns empty list for invalid JSON" do
      assert [] = Chunker.chunk("not json", "search.json")
    end

    test "returns empty list for empty items array" do
      body = Jason.encode!(%{"items" => []})
      assert [] = Chunker.chunk(body, "search.json")
    end
  end

  describe "chunk/2 — markdown" do
    test "splits on headings" do
      section = String.duplicate("This is a long enough paragraph for the chunker filter. ", 2)
      content = "## Section A\n\n#{section}\n\n## Section B\n\n#{section}"

      chunks = Chunker.chunk(content, "guide.md")
      assert length(chunks) >= 2
    end

    test "sets source_reference on every chunk" do
      content = "## Heading\n\n" <> String.duplicate("word ", 20)
      [chunk | _] = Chunker.chunk(content, "docs/guide.md")
      assert chunk.source_reference == "docs/guide.md"
    end
  end

  describe "chunk/2 — elixir source" do
    test "splits on def boundaries" do
      content = """
      defmodule Foo do
        @doc \"Returns the value incremented by one, useful for testing the chunker boundary split.\"
        def bar(x), do: x + 1

        @doc \"Returns the value multiplied by two, another example function for the chunker test.\"
        def baz(x), do: x * 2
      end
      """

      chunks = Chunker.chunk(content, "lib/foo.ex")
      assert length(chunks) >= 1
      assert Enum.all?(chunks, &(&1.metadata.kind in [:code, :prose]))
    end
  end

  describe "chunk/2 — plain text fallback" do
    test "chunks by paragraph for unknown extension" do
      content =
        Enum.map_join(1..5, "\n\n", fn i ->
          "Paragraph #{i}: " <> String.duplicate("word ", 20)
        end)

      chunks = Chunker.chunk(content, "notes.txt")
      assert length(chunks) >= 1
    end
  end
end
