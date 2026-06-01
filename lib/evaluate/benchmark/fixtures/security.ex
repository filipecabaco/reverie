defmodule Evaluate.Benchmark.Fixtures.Security do
  @behaviour Evaluate.Benchmark.Domain

  alias Evaluate.Benchmark.Fixture

  @impl true
  def name, do: "Security"

  @impl true
  def categories do
    [:injection, :auth, :secrets, :rls_and_access, :secure_coding, :incident_response]
  end

  @impl true
  def fixtures do
    [
      %Fixture{
        id: "sec-injection-001",
        category: :injection,
        difficulty: :easy,
        prompt: """
        Review the following Elixir Ecto query for SQL injection risk and fix it:

            def search_users(term) do
              Repo.query!("SELECT * FROM users WHERE name LIKE '%\#{term}%'")
            end

        Explain why the original is dangerous, show the safe version using Ecto's
        query API, and explain what parameterized queries prevent at the database level.
        """,
        test_code: nil,
        tags: [:injection, :sql_injection, :ecto, :secure_coding],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "sec-injection-002",
        category: :injection,
        difficulty: :medium,
        prompt: """
        A Phoenix controller renders user-supplied content in a template.
        Explain how Phoenix/HEEx prevents XSS by default, what you must do to
        opt into raw output, and what the correct pattern is when you genuinely
        need to render safe HTML from a trusted source (e.g. a markdown renderer).
        Show a concrete safe and unsafe example.
        """,
        test_code: nil,
        tags: [:injection, :xss, :phoenix, :templates],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "sec-auth-001",
        category: :auth,
        difficulty: :medium,
        prompt: """
        Implement a secure `Sessions.create/2` function in Elixir that:
        1. Looks up the user by email (timing-safe — does not reveal whether email exists).
        2. Verifies the password using `Bcrypt.verify_pass/2` with a dummy check when user not found.
        3. Returns `{:ok, token}` on success or `{:error, :unauthorized}` on failure — same shape always.
        Explain why the dummy check matters and how it prevents a user enumeration attack.
        """,
        test_code: nil,
        tags: [:auth, :timing_attacks, :user_enumeration, :bcrypt],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "sec-secrets-001",
        category: :secrets,
        difficulty: :easy,
        prompt: """
        A developer committed a database password to a public GitHub repo.
        Walk through your incident response steps in order: what you do in the
        first 5 minutes, what you do in the first hour, and what process changes
        you put in place to prevent recurrence. Be specific about which git commands
        and which platform tools you use.
        """,
        test_code: nil,
        tags: [:secrets, :incident_response, :git, :explanation],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "sec-secrets-002",
        category: :secrets,
        difficulty: :easy,
        prompt: """
        Explain how to manage secrets in a production Elixir/Phoenix application:
        what you use for local dev (`.env` / `runtime.exs`), how secrets are injected
        in a containerized deployment, what `config/runtime.exs` vs `config/prod.exs` is
        for, and why you must never put secrets in `config/config.exs`.
        """,
        test_code: nil,
        tags: [:secrets, :configuration, :phoenix, :deployment],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "sec-access-001",
        category: :rls_and_access,
        difficulty: :medium,
        prompt: """
        A Phoenix API endpoint lets users update their own profile. The controller
        currently does: `Repo.get!(User, params["id"])` then applies the changeset.
        Identify the vulnerability and rewrite the controller action to be safe.
        Explain the general principle (IDOR) and how authorization differs from authentication.
        """,
        test_code: nil,
        tags: [:access_control, :idor, :authorization, :phoenix],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "sec-coding-001",
        category: :secure_coding,
        difficulty: :medium,
        prompt: """
        Review this Elixir function that processes uploaded files and identify all
        security issues:

            def handle_upload(conn, %{"file" => file, "path" => path}) do
              dest = "/var/app/uploads/" <> path <> "/" <> file.filename
              File.cp!(file.path, dest)
              send_resp(conn, 200, dest)
            end

        For each issue: name it, explain the impact, and show the fix.
        """,
        test_code: nil,
        tags: [:secure_coding, :path_traversal, :file_upload, :phoenix],
        scoreable: false,
        sandbox_profile: nil
      }
    ]
  end
end
