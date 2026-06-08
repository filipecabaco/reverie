defmodule Corpus.StoreTest do
  use ExUnit.Case, async: true

  alias Corpus.Store
  alias Research.Brief

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    {:ok, conn} = Store.open(:elixir, dir)
    on_exit(fn -> Store.close(conn) end)
    %{conn: conn, dir: dir}
  end

  describe "open/2" do
    test "creates the database file", %{dir: dir} do
      assert File.exists?(Store.db_path(:elixir, dir))
    end

    test "creates schema tables", %{conn: conn} do
      {:ok, stmt} =
        Exqlite.Sqlite3.prepare(conn, "SELECT name FROM sqlite_master WHERE type='table'")

      {:ok, rows} = Exqlite.Sqlite3.fetch_all(conn, stmt)
      Exqlite.Sqlite3.release(conn, stmt)

      names = Enum.map(rows, fn [name] -> name end)
      assert "chunks" in names
      assert "briefs" in names
    end

    test "open_readonly/2 fails for missing database", %{dir: dir} do
      assert {:error, _} = Store.open_readonly(:nonexistent, dir)
    end
  end

  describe "insert_chunk/2 and search_fts/3" do
    test "inserted chunk is retrievable by keyword", %{conn: conn} do
      {:ok, _id} =
        Store.insert_chunk(conn, %{
          domain: :elixir,
          source_reference: "hexdocs/genserver",
          text: "GenServer is a process that maintains state across calls"
        })

      {:ok, results} = Store.search_fts(conn, "GenServer state", limit: 5)
      assert length(results) >= 1
      assert hd(results).text =~ "GenServer"
    end

    test "search returns empty list for unmatched query", %{conn: conn} do
      Store.insert_chunk(conn, %{domain: :elixir, text: "Pattern matching in Elixir"})
      {:ok, results} = Store.search_fts(conn, "quantum entanglement", limit: 5)
      assert results == []
    end

    test "domain filter restricts results", %{conn: conn} do
      Store.insert_chunk(conn, %{domain: :elixir, text: "Elixir supervisors restart processes"})
      Store.insert_chunk(conn, %{domain: :postgres, text: "Postgres supervisors are not a thing"})

      {:ok, results} = Store.search_fts(conn, "supervisors", domain: :elixir, limit: 10)
      assert Enum.all?(results, &(&1.domain == :elixir))
    end

    test "metadata is stored and returned", %{conn: conn} do
      Store.insert_chunk(conn, %{
        domain: :elixir,
        text: "Task.async runs concurrent work",
        metadata: %{version: "1.18", category: "concurrency"}
      })

      {:ok, [chunk]} = Store.search_fts(conn, "Task async", limit: 5)
      assert chunk.metadata["version"] == "1.18"
    end

    test "inserting same id twice updates the record", %{conn: conn} do
      Store.insert_chunk(conn, %{id: "chunk-1", domain: :elixir, text: "original text"})
      Store.insert_chunk(conn, %{id: "chunk-1", domain: :elixir, text: "original text updated"})

      {:ok, results} = Store.search_fts(conn, "updated", limit: 5)
      assert length(results) >= 1
    end
  end

  describe "indexed_references/2" do
    test "returns {:ok, empty MapSet} when no chunks exist", %{conn: conn} do
      assert {:ok, refs} = Store.indexed_references(conn, :elixir)
      assert MapSet.size(refs) == 0
    end

    test "returns {:ok, MapSet} containing inserted references", %{conn: conn} do
      Store.insert_chunk(conn, %{domain: :elixir, source_reference: "ref-a", text: "alpha"})
      Store.insert_chunk(conn, %{domain: :elixir, source_reference: "ref-b", text: "beta"})

      assert {:ok, refs} = Store.indexed_references(conn, :elixir)
      assert MapSet.member?(refs, "ref-a")
      assert MapSet.member?(refs, "ref-b")
    end

    test "deduplicates multiple chunks with the same source_reference", %{conn: conn} do
      Store.insert_chunk(conn, %{domain: :elixir, source_reference: "ref-dup", text: "chunk one"})
      Store.insert_chunk(conn, %{domain: :elixir, source_reference: "ref-dup", text: "chunk two"})

      assert {:ok, refs} = Store.indexed_references(conn, :elixir)
      assert MapSet.size(refs) == 1
    end

    test "filters by domain — excludes other domains' references", %{conn: conn} do
      Store.insert_chunk(conn, %{
        domain: :elixir,
        source_reference: "elixir-ref",
        text: "elixir stuff"
      })

      Store.insert_chunk(conn, %{
        domain: :postgres,
        source_reference: "pg-ref",
        text: "postgres stuff"
      })

      assert {:ok, refs} = Store.indexed_references(conn, :elixir)
      assert MapSet.member?(refs, "elixir-ref")
      refute MapSet.member?(refs, "pg-ref")
    end
  end

  describe "save_brief/2 and get_brief/2" do
    test "round-trips a brief", %{conn: conn} do
      brief = sample_brief()
      :ok = Store.save_brief(conn, brief)

      {:ok, loaded} = Store.get_brief(conn, brief.id)
      assert loaded.id == brief.id
      assert loaded.topic == brief.topic
      assert loaded.domain == brief.domain
      assert loaded.status == brief.status
      assert loaded.facts == brief.facts
    end

    test "returns :not_found for missing brief", %{conn: conn} do
      assert {:error, :not_found} = Store.get_brief(conn, "nonexistent-id")
    end

    test "saving twice updates the record", %{conn: conn} do
      %Brief{} = brief = sample_brief()
      Store.save_brief(conn, brief)
      Store.save_brief(conn, %Brief{brief | status: :verified})

      {:ok, loaded} = Store.get_brief(conn, brief.id)
      assert loaded.status == :verified
    end
  end

  describe "list_briefs/2" do
    test "returns all briefs for a domain", %{conn: conn} do
      Store.save_brief(conn, sample_brief(%{id: "b1", topic: "GenServer"}))
      Store.save_brief(conn, sample_brief(%{id: "b2", topic: "Supervisors"}))

      {:ok, briefs} = Store.list_briefs(conn, domain: :elixir)
      assert length(briefs) == 2
    end

    test "filters by status", %{conn: conn} do
      Store.save_brief(conn, sample_brief(%{id: "b1", status: :draft}))
      Store.save_brief(conn, sample_brief(%{id: "b2", status: :verified}))

      {:ok, briefs} = Store.list_briefs(conn, status: :verified)
      assert length(briefs) == 1
      assert hd(briefs).status == :verified
    end

    test "returns empty list when no briefs match", %{conn: conn} do
      {:ok, briefs} = Store.list_briefs(conn, domain: :elixir)
      assert briefs == []
    end
  end

  defp sample_brief(overrides \\ %{}) do
    base = %Brief{
      id: overrides[:id] || "brief-test-001",
      domain: :elixir,
      topic: overrides[:topic] || "GenServer",
      status: overrides[:status] || :draft,
      facts: ["GenServer processes one message at a time", "Use call for synchronous replies"],
      examples: nil,
      prohibited_patterns: ["do not use :infinity timeout"],
      sources: [
        %{
          kind: :official_docs,
          reference: "https://hexdocs.pm/elixir/GenServer.html",
          retrieved_at: DateTime.utc_now()
        }
      ],
      package_versions: %{"elixir" => "1.18"},
      created_at: DateTime.utc_now() |> DateTime.truncate(:second),
      expires_at: nil
    }

    Map.merge(base, Map.new(overrides, fn {k, v} -> {k, v} end))
  end
end
