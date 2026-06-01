defmodule Evaluate.Benchmark.Fixtures.TypeScript do
  @behaviour Evaluate.Benchmark.Domain

  alias Evaluate.Benchmark.Fixture

  @impl true
  def name, do: "TypeScript"

  @impl true
  def categories do
    [:types, :generics, :async, :error_handling, :patterns, :debugging]
  end

  @impl true
  def fixtures do
    [
      %Fixture{
        id: "ts-types-001",
        category: :types,
        difficulty: :easy,
        prompt: """
        Define TypeScript types for an API response envelope:
        - `ApiResponse<T>` — either `{ ok: true; data: T }` or `{ ok: false; error: string }`.
        - A `User` type with `id: number`, `name: string`, `email: string`, `role: "admin" | "member"`.
        - A `UserResponse` = `ApiResponse<User>`.
        Write a type-safe `unwrap<T>(r: ApiResponse<T>): T` function that throws on error.
        """,
        test_code: nil,
        tags: [:types, :discriminated_union, :generics],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "ts-generics-001",
        category: :generics,
        difficulty: :medium,
        prompt: """
        Implement a generic `Result<T, E>` type (similar to Rust's Result) in TypeScript with:
        - `ok<T>(value: T): Result<T, never>`
        - `err<E>(error: E): Result<never, E>`
        - `Result.map<T, U, E>(r: Result<T, E>, fn: (v: T) => U): Result<U, E>`
        - `Result.flatMap<T, U, E>(r: Result<T, E>, fn: (v: T) => Result<U, E>): Result<U, E>`
        - `Result.unwrapOr<T, E>(r: Result<T, E>, fallback: T): T`
        """,
        test_code: nil,
        tags: [:generics, :functional, :result_type],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "ts-async-001",
        category: :async,
        difficulty: :medium,
        prompt: """
        Implement `fetchWithRetry<T>(url: string, opts: { retries: number; delayMs: number }): Promise<T>`
        that retries on network errors with exponential backoff (delay doubles each attempt).
        Type it correctly so the caller gets `T` back without casting.
        Explain why you should not use `any` in the return type.
        """,
        test_code: nil,
        tags: [:async, :retry, :generics, :error_handling],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "ts-error-001",
        category: :error_handling,
        difficulty: :medium,
        prompt: """
        You have an async function that calls three external APIs sequentially.
        Each can throw. Rewrite it so: failures are represented as typed errors
        (not thrown exceptions), all three calls still complete even if one fails,
        and the caller can distinguish which API failed. Do not use `any`.
        """,
        test_code: nil,
        tags: [:error_handling, :async, :type_safety],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "ts-patterns-001",
        category: :patterns,
        difficulty: :medium,
        prompt: """
        Implement a type-safe event emitter in TypeScript where:
        - Event names and their payload types are declared upfront via a generic map.
        - `on(event, handler)` and `emit(event, payload)` are fully typed — the compiler
          rejects wrong payload types.
        - Handlers can be removed with `off(event, handler)`.
        Show a usage example with at least two distinct event types.
        """,
        test_code: nil,
        tags: [:patterns, :generics, :event_emitter, :type_safety],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "ts-debug-001",
        category: :debugging,
        difficulty: :easy,
        prompt: """
        The following TypeScript compiles but produces wrong output at runtime.
        Identify and fix the bug:

            async function getNames(ids: number[]): Promise<string[]> {
              return ids.map(async (id) => {
                const user = await fetchUser(id);
                return user.name;
              });
            }
        """,
        test_code: nil,
        tags: [:debugging, :async, :map_vs_promise_all],
        scoreable: false,
        sandbox_profile: nil
      }
    ]
  end
end
