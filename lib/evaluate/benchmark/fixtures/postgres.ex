defmodule Evaluate.Benchmark.Fixtures.Postgres do
  @behaviour Evaluate.Benchmark.Domain

  alias Evaluate.Benchmark.Fixture

  @impl true
  def name, do: "Postgres"

  @impl true
  def categories do
    [:schema_design, :querying, :indexing, :transactions, :performance, :debugging]
  end

  @impl true
  def fixtures do
    [
      %Fixture{
        id: "pg-schema-001",
        category: :schema_design,
        difficulty: :easy,
        prompt: """
        Design a normalized schema for a blog platform with users, posts, tags, and
        post-tag associations. Write the CREATE TABLE statements with appropriate
        primary keys, foreign keys, NOT NULL constraints, and indexes.
        Explain your normalization choices.
        """,
        test_code: nil,
        tags: [:schema_design, :normalization, :constraints],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "pg-schema-002",
        category: :schema_design,
        difficulty: :medium,
        prompt: """
        A `payments` table records transactions. Add an `audit_log` table that
        automatically captures inserts, updates, and deletes on `payments` using
        a trigger. Show: the audit table DDL, the trigger function, and the trigger
        binding. The log must record: operation type, old row (JSON), new row (JSON),
        changed_at timestamp, and the current database user.
        """,
        test_code: nil,
        tags: [:schema_design, :triggers, :audit],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "pg-query-001",
        category: :querying,
        difficulty: :medium,
        prompt: """
        Write a query against `orders(id, customer_id, status, total, created_at)`
        and `customers(id, name, country)` that returns, per country, the number of
        orders, total revenue, average order value, and the name of the top customer
        (by revenue) in that country. Use a CTE and a window function.
        """,
        test_code: nil,
        tags: [:querying, :cte, :window_functions, :aggregation],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "pg-query-002",
        category: :querying,
        difficulty: :medium,
        prompt: """
        Write a recursive CTE that traverses an employee hierarchy table
        `employees(id, name, manager_id)` and returns each employee's full
        reporting chain from root to leaf, with their depth level.
        """,
        test_code: nil,
        tags: [:querying, :cte, :recursive, :hierarchical],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "pg-index-001",
        category: :indexing,
        difficulty: :medium,
        prompt: """
        A query on `events(user_id, event_type, created_at, payload)` filters by
        `user_id` and `event_type`, orders by `created_at` DESC, and fetches the
        first 20 rows. The table has 50M rows.

        1. What index would you create and why?
        2. What does `EXPLAIN ANALYZE` output tell you about whether the index is used?
        3. When would a partial index be better than a full composite index here?
        """,
        test_code: nil,
        tags: [:indexing, :performance, :explain_analyze],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "pg-tx-001",
        category: :transactions,
        difficulty: :medium,
        prompt: """
        Implement a `transfer_funds(from_account_id, to_account_id, amount)` stored
        procedure in PL/pgSQL that:
        1. Locks both account rows (deadlock-safe ordering).
        2. Checks sufficient balance, raises an exception if not.
        3. Debits from and credits to atomically.
        4. Inserts a row into `transfers(from_id, to_id, amount, transferred_at)`.
        Use `BEGIN ... EXCEPTION ... END` for error handling.
        """,
        test_code: nil,
        tags: [:transactions, :plpgsql, :locking, :atomicity],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "pg-perf-001",
        category: :performance,
        difficulty: :hard,
        prompt: """
        A query that was fast six months ago now takes 30 seconds. Walk through your
        full diagnostic process: what Postgres system views and functions you check,
        what `EXPLAIN (ANALYZE, BUFFERS)` output you look for, what causes you suspect
        (statistics staleness, index bloat, sequential scans, lock contention, N+1),
        and how you confirm each hypothesis before acting.
        """,
        test_code: nil,
        tags: [:performance, :debugging, :diagnostics, :explanation],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "pg-debug-001",
        category: :debugging,
        difficulty: :medium,
        prompt: """
        A query that was running in 50ms last week now takes 45 seconds.
        No schema changes were made. Walk through your full investigation:
        which Postgres system views you check first (`pg_stat_user_tables`,
        `pg_statio_user_indexes`, `pg_locks`), what `EXPLAIN (ANALYZE, BUFFERS)`
        output tells you, how you check for bloat and stale statistics, and how
        you identify whether the regression is from a plan change, lock contention,
        or autovacuum not keeping up.
        """,
        test_code: nil,
        tags: [:debugging, :performance, :diagnostics, :explain_analyze],
        scoreable: false,
        sandbox_profile: nil
      }
    ]
  end
end
