defmodule Evaluate.Benchmark.Fixtures.Supabase do
  @behaviour Evaluate.Benchmark.Domain

  alias Evaluate.Benchmark.Fixture

  @impl true
  def name, do: "Supabase"

  @impl true
  def categories do
    [:rls, :auth, :realtime, :edge_functions, :storage, :migrations, :debugging]
  end

  @impl true
  def fixtures do
    [
      %Fixture{
        id: "supa-rls-001",
        category: :rls,
        difficulty: :easy,
        prompt: """
        Enable RLS on a `posts` table and write policies so that:
        - Any authenticated user can read all published posts (`published = true`).
        - A user can only read their own draft posts (`published = false AND user_id = auth.uid()`).
        - A user can only insert, update, and delete their own posts (`user_id = auth.uid()`).
        Show the `ALTER TABLE` and all four `CREATE POLICY` statements.
        """,
        test_code: nil,
        tags: [:rls, :auth, :policies],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "supa-rls-002",
        category: :rls,
        difficulty: :medium,
        prompt: """
        A `documents` table is shared across organizations. Each user belongs to one
        organization (`user_organizations(user_id, org_id)`). Write RLS policies so
        users can only see documents belonging to their organization.
        The policy must not cause N+1 queries — explain how you verify it with EXPLAIN.
        """,
        test_code: nil,
        tags: [:rls, :multi_tenant, :performance],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "supa-auth-001",
        category: :auth,
        difficulty: :easy,
        prompt: """
        Explain how Supabase Auth JWTs work end-to-end: what claims are in the token,
        how `auth.uid()` resolves inside a Postgres session, and how RLS policies
        consume those claims. What happens when a token expires mid-request?
        """,
        test_code: nil,
        tags: [:auth, :jwt, :explanation],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "supa-realtime-001",
        category: :realtime,
        difficulty: :medium,
        prompt: """
        Write the client-side JavaScript to subscribe to real-time changes on a
        `messages` table filtered to a specific `room_id`, handling INSERT, UPDATE,
        and DELETE events. Show how to unsubscribe cleanly on component unmount.
        Explain what Postgres configuration Supabase requires for realtime to work.
        """,
        test_code: nil,
        tags: [:realtime, :subscriptions, :javascript],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "supa-edge-001",
        category: :edge_functions,
        difficulty: :medium,
        prompt: """
        Write a Supabase Edge Function that receives a webhook from Stripe, verifies
        the signature using the Stripe-Signature header, and upserts the subscription
        status into a `subscriptions` table via the Supabase service role client.
        Handle verification failure with a 400 response. Use Deno/TypeScript.
        """,
        test_code: nil,
        tags: [:edge_functions, :webhooks, :stripe, :typescript],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "supa-migration-001",
        category: :migrations,
        difficulty: :easy,
        prompt: """
        You need to add a `profile_picture_url` column to a `users` table that
        already has millions of rows in production. Write the Supabase migration
        file. Explain: should you use NOT NULL with a default? What are the
        lock implications on Postgres 12+ vs earlier versions? How do you
        verify the migration ran correctly?
        """,
        test_code: nil,
        tags: [:migrations, :schema, :production_safety],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "supa-debug-001",
        category: :debugging,
        difficulty: :medium,
        prompt: """
        A user reports they cannot read rows from a table even though you have
        a permissive SELECT policy in place. Walk through your full debugging process:
        which Supabase dashboard panels you check, how you use `SET ROLE` and
        `SET request.jwt.claims` to impersonate the user in psql, what `EXPLAIN`
        output indicates a policy problem, and the three most common root causes.
        """,
        test_code: nil,
        tags: [:debugging, :rls, :diagnostics, :explanation],
        scoreable: false,
        sandbox_profile: nil
      }
    ]
  end
end
