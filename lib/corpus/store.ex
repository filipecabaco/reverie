defmodule Corpus.Store do
  @moduledoc """
  Per-domain SQLite corpus store — the single source of truth for a domain (§1.6, §3.8).

  Each domain has its own database at `data/<domain>/corpus.db`.
  The store holds:
    - `chunks`      — source text passages with metadata
    - `chunks_fts`  — FTS5 standalone full-text index (id + text)
    - `briefs`      — research briefs produced by Research.Agent

  Connections are not shared across processes. Callers open a connection, use it,
  and close it. For concurrent reads, open multiple read-only connections (WAL mode).

  sqlite-vec for vector retrieval is intentionally deferred until it stabilises (pre-v1).
  FTS5 is the default retrieval path.
  """

  alias Exqlite.Sqlite3

  @type conn :: reference()

  @doc "Open (or create) the corpus database for a domain."
  @spec open(atom(), Path.t()) :: {:ok, conn()} | {:error, term()}
  def open(domain, data_dir \\ "data") do
    path = db_path(domain, data_dir)
    File.mkdir_p!(Path.dirname(path))

    with {:ok, conn} <- Sqlite3.open(path) do
      :ok = Sqlite3.execute(conn, "PRAGMA journal_mode=WAL")
      :ok = Sqlite3.execute(conn, "PRAGMA foreign_keys=ON")
      :ok = setup_schema(conn)
      {:ok, conn}
    end
  end

  @doc "Open an existing database read-only. Fails if the database does not exist."
  @spec open_readonly(atom(), Path.t()) :: {:ok, conn()} | {:error, term()}
  def open_readonly(domain, data_dir \\ "data") do
    path = db_path(domain, data_dir)

    if File.exists?(path) do
      Sqlite3.open(path, mode: :readonly)
    else
      {:error, {:not_found, path}}
    end
  end

  @doc "Close a connection."
  @spec close(conn()) :: :ok
  def close(conn), do: Sqlite3.close(conn)

  # ---------------------------------------------------------------------------
  # Chunks
  # ---------------------------------------------------------------------------

  @doc "Insert a source text chunk."
  @spec insert_chunk(conn(), map()) :: {:ok, String.t()} | {:error, term()}
  def insert_chunk(conn, chunk) do
    id = chunk[:id] || chunk["id"] || generate_id()
    text = chunk[:text] || chunk["text"]
    domain = chunk[:domain] || chunk["domain"]
    source_reference = chunk[:source_reference] || chunk["source_reference"]
    metadata = Jason.encode!(chunk[:metadata] || chunk["metadata"] || %{})
    now = DateTime.to_iso8601(DateTime.utc_now())

    with {:ok, stmt} <-
           Sqlite3.prepare(
             conn,
             "INSERT OR REPLACE INTO chunks (id, domain, source_reference, text, metadata, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)"
           ),
         :ok <- Sqlite3.bind(stmt, [id, to_string(domain), source_reference, text, metadata, now]),
         _ <- Sqlite3.step(conn, stmt),
         :ok <- Sqlite3.release(conn, stmt),
         {:ok, fts_stmt} <-
           Sqlite3.prepare(conn, "INSERT OR REPLACE INTO chunks_fts(id, text) VALUES (?1, ?2)"),
         :ok <- Sqlite3.bind(fts_stmt, [id, text]),
         _ <- Sqlite3.step(conn, fts_stmt),
         :ok <- Sqlite3.release(conn, fts_stmt) do
      {:ok, id}
    end
  end

  @doc "Full-text search over chunks. Returns up to `limit` matching chunks."
  @spec search_fts(conn(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search_fts(conn, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    domain = Keyword.get(opts, :domain)

    {sql, params} =
      if domain do
        {
          """
          SELECT c.id, c.domain, c.source_reference, c.text, c.metadata
          FROM chunks_fts f
          JOIN chunks c ON c.id = f.id
          WHERE f.text MATCH ?1 AND c.domain = ?2
          ORDER BY rank LIMIT ?3
          """,
          [query, to_string(domain), limit]
        }
      else
        {
          """
          SELECT c.id, c.domain, c.source_reference, c.text, c.metadata
          FROM chunks_fts f
          JOIN chunks c ON c.id = f.id
          WHERE f.text MATCH ?1
          ORDER BY rank LIMIT ?2
          """,
          [query, limit]
        }
      end

    with {:ok, stmt} <- Sqlite3.prepare(conn, sql),
         :ok <- Sqlite3.bind(stmt, params),
         {:ok, rows} <- Sqlite3.fetch_all(conn, stmt),
         :ok <- Sqlite3.release(conn, stmt) do
      chunks =
        Enum.map(rows, fn [id, domain, source_ref, text, meta_json] ->
          %{
            id: id,
            domain: String.to_existing_atom(domain),
            source_reference: source_ref,
            text: text,
            metadata: Jason.decode!(meta_json || "{}")
          }
        end)

      {:ok, chunks}
    end
  end

  # ---------------------------------------------------------------------------
  # Briefs
  # ---------------------------------------------------------------------------

  @doc "Persist a Research.Brief to the store."
  @spec save_brief(conn(), Research.Brief.t()) :: :ok | {:error, term()}
  def save_brief(conn, %Research.Brief{} = brief) do
    params = [
      brief.id,
      to_string(brief.domain),
      brief.topic,
      to_string(brief.status),
      Jason.encode!(brief.facts),
      Jason.encode!(brief.examples),
      Jason.encode!(brief.prohibited_patterns),
      Jason.encode!(Enum.map(brief.sources || [], &serialize_source/1)),
      Jason.encode!(brief.package_versions || %{}),
      DateTime.to_iso8601(brief.created_at),
      brief.expires_at && DateTime.to_iso8601(brief.expires_at)
    ]

    with {:ok, stmt} <-
           Sqlite3.prepare(
             conn,
             """
             INSERT OR REPLACE INTO briefs
               (id, domain, topic, status, facts, examples, prohibited_patterns,
                sources, package_versions, created_at, expires_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
             """
           ),
         :ok <- Sqlite3.bind(stmt, params),
         _ <- Sqlite3.step(conn, stmt),
         :ok <- Sqlite3.release(conn, stmt) do
      :ok
    end
  end

  @doc "Retrieve a brief by ID."
  @spec get_brief(conn(), String.t()) :: {:ok, Research.Brief.t()} | {:error, :not_found | term()}
  def get_brief(conn, brief_id) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, "SELECT * FROM briefs WHERE id = ?1"),
         :ok <- Sqlite3.bind(stmt, [brief_id]),
         result <- Sqlite3.step(conn, stmt),
         :ok <- Sqlite3.release(conn, stmt) do
      case result do
        {:row, row} -> {:ok, row_to_brief(row)}
        :done -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc "List briefs, optionally filtered by domain and/or status."
  @spec list_briefs(conn(), keyword()) :: {:ok, [Research.Brief.t()]} | {:error, term()}
  def list_briefs(conn, opts \\ []) do
    domain = Keyword.get(opts, :domain)
    status = Keyword.get(opts, :status)

    {where, params} = build_brief_filter(domain, status)

    with {:ok, stmt} <-
           Sqlite3.prepare(conn, "SELECT * FROM briefs#{where} ORDER BY created_at DESC"),
         :ok <- Sqlite3.bind(stmt, params),
         {:ok, rows} <- Sqlite3.fetch_all(conn, stmt),
         :ok <- Sqlite3.release(conn, stmt) do
      {:ok, Enum.map(rows, &row_to_brief/1)}
    end
  end

  # ---------------------------------------------------------------------------
  # Schema
  # ---------------------------------------------------------------------------

  @doc "Create tables and indexes if they do not already exist."
  @spec setup_schema(conn()) :: :ok
  def setup_schema(conn) do
    :ok =
      Sqlite3.execute(conn, """
      CREATE TABLE IF NOT EXISTS chunks (
        id TEXT PRIMARY KEY,
        domain TEXT NOT NULL,
        source_reference TEXT,
        text TEXT NOT NULL,
        metadata TEXT,
        created_at TEXT NOT NULL
      )
      """)

    :ok =
      Sqlite3.execute(conn, """
      CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts
      USING fts5(id UNINDEXED, text, tokenize='porter unicode61')
      """)

    :ok =
      Sqlite3.execute(conn, """
      CREATE TABLE IF NOT EXISTS briefs (
        id TEXT PRIMARY KEY,
        domain TEXT NOT NULL,
        topic TEXT NOT NULL,
        status TEXT NOT NULL,
        facts TEXT NOT NULL,
        examples TEXT,
        prohibited_patterns TEXT,
        sources TEXT NOT NULL,
        package_versions TEXT,
        created_at TEXT NOT NULL,
        expires_at TEXT
      )
      """)

    :ok =
      Sqlite3.execute(
        conn,
        "CREATE INDEX IF NOT EXISTS briefs_domain_status ON briefs(domain, status)"
      )

    :ok = Sqlite3.execute(conn, "CREATE INDEX IF NOT EXISTS chunks_domain ON chunks(domain)")
  end

  @doc "Returns a MapSet of source references already indexed for a domain."
  @spec indexed_references(conn(), atom()) :: {:ok, MapSet.t(String.t())} | {:error, term()}
  def indexed_references(conn, domain) do
    sql = "SELECT DISTINCT source_reference FROM chunks WHERE domain = ?1"

    with {:ok, stmt} <- Sqlite3.prepare(conn, sql),
         :ok <- Sqlite3.bind(stmt, [to_string(domain)]),
         {:ok, rows} <- Sqlite3.fetch_all(conn, stmt),
         :ok <- Sqlite3.release(conn, stmt) do
      {:ok, rows |> Enum.map(fn [ref] -> ref end) |> MapSet.new()}
    end
  end

  @doc "Canonical path for a domain's corpus database."
  @spec db_path(atom(), Path.t()) :: Path.t()
  def db_path(domain, data_dir \\ "data") do
    Path.join([data_dir, to_string(domain), "corpus.db"])
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp build_brief_filter(nil, nil), do: {"", []}
  defp build_brief_filter(domain, nil), do: {" WHERE domain = ?1", [to_string(domain)]}
  defp build_brief_filter(nil, status), do: {" WHERE status = ?1", [to_string(status)]}

  defp build_brief_filter(domain, status),
    do: {" WHERE domain = ?1 AND status = ?2", [to_string(domain), to_string(status)]}

  defp row_to_brief([
         id,
         domain,
         topic,
         status,
         facts,
         examples,
         prohibited,
         sources,
         versions,
         created_at,
         expires_at
       ]) do
    %Research.Brief{
      id: id,
      domain: String.to_existing_atom(domain),
      topic: topic,
      status: String.to_existing_atom(status),
      facts: Jason.decode!(facts),
      examples: decode_nullable(examples),
      prohibited_patterns: decode_nullable(prohibited),
      sources: Jason.decode!(sources),
      package_versions: decode_nullable(versions),
      created_at: parse_datetime(created_at),
      expires_at: parse_datetime(expires_at)
    }
  end

  defp decode_nullable(nil), do: nil
  defp decode_nullable(json), do: Jason.decode!(json)

  defp parse_datetime(nil), do: nil
  defp parse_datetime(str), do: elem(DateTime.from_iso8601(str), 1)

  defp serialize_source(%{retrieved_at: %DateTime{} = dt} = s) do
    s
    |> Map.put(:retrieved_at, DateTime.to_iso8601(dt))
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  defp serialize_source(s), do: s

  defp generate_id do
    8 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
