defmodule Evaluate.Benchmark.Fixtures.Elixir do
  @behaviour Evaluate.Benchmark.Domain

  alias Evaluate.Benchmark.Fixture

  @impl true
  def name, do: "Elixir"

  @impl true
  def categories do
    [:pattern_matching, :genserver, :supervision, :ecto, :exunit, :otp, :debugging]
  end

  @impl true
  def fixtures do
    pattern_matching() ++
      genserver() ++ supervision() ++ ecto() ++ exunit() ++ otp() ++ debugging()
  end

  defp pattern_matching do
    [
      %Fixture{
        id: "elixir-pm-001",
        category: :pattern_matching,
        difficulty: :easy,
        prompt: """
        Implement a `StatusMessage` module with a `describe/1` function that uses
        function-head pattern matching to return:
          - `{:ok, value}`     → `"Success: \#{inspect(value)}"`
          - `{:error, reason}` → `"Error: \#{inspect(reason)}"`
          - `:loading`         → `"Loading..."`
          - anything else      → `"Unknown"`
        """,
        test_code: """
        defmodule StatusMessageTest do
          use ExUnit.Case
          test "ok" do assert StatusMessage.describe({:ok, 42}) == "Success: 42" end
          test "error" do assert StatusMessage.describe({:error, :not_found}) == "Error: :not_found" end
          test "loading" do assert StatusMessage.describe(:loading) == "Loading..." end
          test "unknown" do assert StatusMessage.describe(:other) == "Unknown" end
        end
        """,
        tags: [:pattern_matching, :function_heads],
        scoreable: true,
        sandbox_profile: :stdlib
      },
      %Fixture{
        id: "elixir-pm-002",
        category: :pattern_matching,
        difficulty: :easy,
        prompt: """
        Implement `Config.database_host/1` that takes a nested config map such as
        `%{database: %{host: "localhost", port: 5432}}` and returns the host string.
        Use pattern matching directly in the function argument (not a `case` body).
        """,
        test_code: """
        defmodule ConfigTest do
          use ExUnit.Case
          test "extracts host" do
            cfg = %{database: %{host: "db.example.com", port: 5432}}
            assert Config.database_host(cfg) == "db.example.com"
          end
        end
        """,
        tags: [:pattern_matching, :destructuring, :maps],
        scoreable: true,
        sandbox_profile: :stdlib
      },
      %Fixture{
        id: "elixir-pm-003",
        category: :pattern_matching,
        difficulty: :easy,
        prompt: """
        Implement `Math.sum/1` that sums a list of numbers using recursion and
        head/tail pattern matching. Do not use `Enum`. Handle the empty-list base case explicitly.
        """,
        test_code: """
        defmodule MathTest do
          use ExUnit.Case
          test "empty list" do assert Math.sum([]) == 0 end
          test "single element" do assert Math.sum([7]) == 7 end
          test "multiple elements" do assert Math.sum([1, 2, 3, 4]) == 10 end
          test "negative numbers" do assert Math.sum([-1, 1]) == 0 end
        end
        """,
        tags: [:pattern_matching, :recursion, :lists],
        scoreable: true,
        sandbox_profile: :stdlib
      },
      %Fixture{
        id: "elixir-pm-004",
        category: :pattern_matching,
        difficulty: :medium,
        prompt: """
        Implement `UserService.create/1` using a `with` expression that:
        1. Validates `:name` is a non-empty string → `{:error, :missing_name}` otherwise.
        2. Validates `:age` is a positive integer → `{:error, :invalid_age}` otherwise.
        3. Returns `{:ok, %{name: name, age: age}}` if both pass.
        Use private helper functions for each validation.
        """,
        test_code: """
        defmodule UserServiceTest do
          use ExUnit.Case
          test "valid" do
            assert {:ok, %{name: "Alice", age: 30}} = UserService.create(%{name: "Alice", age: 30})
          end
          test "missing name" do assert {:error, :missing_name} = UserService.create(%{age: 30}) end
          test "empty name" do assert {:error, :missing_name} = UserService.create(%{name: "", age: 30}) end
          test "negative age" do assert {:error, :invalid_age} = UserService.create(%{name: "Alice", age: -1}) end
          test "zero age" do assert {:error, :invalid_age} = UserService.create(%{name: "Alice", age: 0}) end
        end
        """,
        tags: [:pattern_matching, :with, :validation],
        scoreable: true,
        sandbox_profile: :stdlib
      }
    ]
  end

  defp genserver do
    [
      %Fixture{
        id: "elixir-gs-001",
        category: :genserver,
        difficulty: :easy,
        prompt: """
        Implement a `Counter` GenServer with:
          - `Counter.start_link(initial \\\\ 0)`
          - `Counter.increment(pid)` (cast)
          - `Counter.get(pid)` (call)
          - `Counter.reset(pid)` (cast)
        """,
        test_code: """
        defmodule CounterTest do
          use ExUnit.Case
          test "default start" do {:ok, pid} = Counter.start_link(); assert Counter.get(pid) == 0 end
          test "initial value" do {:ok, pid} = Counter.start_link(10); assert Counter.get(pid) == 10 end
          test "increment" do
            {:ok, pid} = Counter.start_link()
            Counter.increment(pid); Counter.increment(pid)
            assert Counter.get(pid) == 2
          end
          test "reset" do
            {:ok, pid} = Counter.start_link(5)
            Counter.reset(pid)
            assert Counter.get(pid) == 0
          end
        end
        """,
        tags: [:genserver, :otp, :state],
        scoreable: true,
        sandbox_profile: :stdlib
      },
      %Fixture{
        id: "elixir-gs-002",
        category: :genserver,
        difficulty: :easy,
        prompt: """
        Implement a `KVStore` GenServer backed by a map with:
          - `KVStore.start_link()`
          - `KVStore.put(pid, key, value)`
          - `KVStore.get(pid, key)` → value or `nil`
          - `KVStore.delete(pid, key)`
        """,
        test_code: """
        defmodule KVStoreTest do
          use ExUnit.Case
          setup do {:ok, pid} = KVStore.start_link(); %{pid: pid} end
          test "put and get", %{pid: pid} do KVStore.put(pid, :k, "v"); assert KVStore.get(pid, :k) == "v" end
          test "missing key", %{pid: pid} do assert KVStore.get(pid, :x) == nil end
          test "delete", %{pid: pid} do
            KVStore.put(pid, :k, 1); KVStore.delete(pid, :k)
            assert KVStore.get(pid, :k) == nil
          end
        end
        """,
        tags: [:genserver, :otp, :state, :maps],
        scoreable: true,
        sandbox_profile: :stdlib
      },
      %Fixture{
        id: "elixir-gs-003",
        category: :genserver,
        difficulty: :medium,
        prompt: """
        Implement a `Ticker` GenServer that schedules a `:tick` message to itself
        every 100 ms using `Process.send_after/3`, reschedules on each tick, counts
        ticks in state, and exposes `Ticker.start_link()` and `Ticker.tick_count(pid)`.
        """,
        test_code: """
        defmodule TickerTest do
          use ExUnit.Case
          test "counts ticks" do
            {:ok, pid} = Ticker.start_link()
            Process.sleep(350)
            assert Ticker.tick_count(pid) >= 2
          end
        end
        """,
        tags: [:genserver, :handle_info, :scheduling],
        scoreable: true,
        sandbox_profile: :stdlib
      },
      %Fixture{
        id: "elixir-gs-004",
        category: :genserver,
        difficulty: :medium,
        prompt: """
        Explain the difference between `GenServer.call/3` and `GenServer.cast/2`.
        Cover synchrony, return values, timeout behaviour, and backpressure.
        Give a concrete example where using cast instead of call introduces a race condition.
        """,
        test_code: nil,
        tags: [:genserver, :otp, :concurrency, :explanation],
        scoreable: false,
        sandbox_profile: nil
      }
    ]
  end

  defp supervision do
    [
      %Fixture{
        id: "elixir-sv-001",
        category: :supervision,
        difficulty: :easy,
        prompt: """
        Implement `MyApp.Supervisor` with `:one_for_one` supervising two minimal GenServer
        workers: `MyApp.Worker.A` and `MyApp.Worker.B`, each started with `start_link([])`.
        """,
        test_code: """
        defmodule MyApp.SupervisorTest do
          use ExUnit.Case
          test "starts both workers" do
            {:ok, sup} = MyApp.Supervisor.start_link([])
            assert length(Supervisor.which_children(sup)) == 2
          end
        end
        """,
        tags: [:supervision, :otp, :one_for_one],
        scoreable: true,
        sandbox_profile: :stdlib
      },
      %Fixture{
        id: "elixir-sv-002",
        category: :supervision,
        difficulty: :medium,
        prompt: """
        Explain the difference between `:one_for_one`, `:one_for_all`, and `:rest_for_one`
        supervision strategies. For each, describe a real scenario where it is the correct choice.
        """,
        test_code: nil,
        tags: [:supervision, :otp, :explanation],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "elixir-sv-003",
        category: :supervision,
        difficulty: :medium,
        prompt: """
        Implement `JobSupervisor` using `DynamicSupervisor` with:
          - `JobSupervisor.start_link()`
          - `JobSupervisor.start_job(sup, id)` → `{:ok, pid}`
          - `JobSupervisor.count(sup)` → number of running jobs
        Also implement a stub `Job` GenServer accepting `Job.start_link(id)`.
        """,
        test_code: """
        defmodule JobSupervisorTest do
          use ExUnit.Case
          test "starts and counts jobs" do
            {:ok, sup} = JobSupervisor.start_link()
            {:ok, _} = JobSupervisor.start_job(sup, 1)
            {:ok, _} = JobSupervisor.start_job(sup, 2)
            assert JobSupervisor.count(sup) == 2
          end
        end
        """,
        tags: [:supervision, :dynamic_supervisor, :otp],
        scoreable: true,
        sandbox_profile: :stdlib
      }
    ]
  end

  defp ecto do
    [
      %Fixture{
        id: "elixir-ec-001",
        category: :ecto,
        difficulty: :easy,
        prompt: """
        Write an Ecto query fetching all `User` records where `active` is true,
        ordered by `inserted_at` descending, selecting only `:id`, `:name`, `:email`.
        Use `MyApp.Repo` and show the result of `Repo.all/1`.
        """,
        test_code: nil,
        tags: [:ecto, :query, :select],
        scoreable: false,
        sandbox_profile: :ecto
      },
      %Fixture{
        id: "elixir-ec-002",
        category: :ecto,
        difficulty: :medium,
        prompt: """
        Implement `User.changeset/2` for a schema with `:name` (required, min 2 chars),
        `:email` (required, format validated), `:age` (optional, >= 18).
        Use `cast`, `validate_required`, `validate_length`, `validate_format`, `validate_number`.
        """,
        test_code: nil,
        tags: [:ecto, :changeset, :validation],
        scoreable: false,
        sandbox_profile: :ecto
      },
      %Fixture{
        id: "elixir-ec-003",
        category: :ecto,
        difficulty: :medium,
        prompt: """
        Write an Ecto migration that creates a `posts` table with `:title` (string, not null),
        `:body` (text), `:published` (boolean, default false), `:user_id` (references users),
        timestamps, and an index on `user_id`. Use `change/0`.
        """,
        test_code: nil,
        tags: [:ecto, :migration, :schema],
        scoreable: false,
        sandbox_profile: :ecto
      }
    ]
  end

  defp exunit do
    [
      %Fixture{
        id: "elixir-ex-001",
        category: :exunit,
        difficulty: :easy,
        prompt: """
        Implement the `Stack` module so the following tests pass:
        `Stack.new/0`, `Stack.push/2`, `Stack.pop/1` → `{value, rest}`,
        `Stack.peek/1`, `Stack.empty?/1`.
        """,
        test_code: """
        defmodule StackTest do
          use ExUnit.Case
          test "push adds to top" do
            s = Stack.new() |> Stack.push(1) |> Stack.push(2)
            assert Stack.peek(s) == 2
          end
          test "pop removes from top" do
            s = Stack.new() |> Stack.push(1) |> Stack.push(2)
            {v, rest} = Stack.pop(s)
            assert v == 2 and Stack.peek(rest) == 1
          end
          test "empty?" do
            assert Stack.empty?(Stack.new())
            refute Stack.empty?(Stack.push(Stack.new(), 1))
          end
        end
        """,
        tags: [:exunit, :data_structures],
        scoreable: true,
        sandbox_profile: :stdlib
      },
      %Fixture{
        id: "elixir-ex-002",
        category: :exunit,
        difficulty: :medium,
        prompt: """
        Explain when `async: false` is necessary in ExUnit. What global state causes
        async tests to interfere? Give two concrete examples from Elixir/OTP code.
        """,
        test_code: nil,
        tags: [:exunit, :concurrency, :explanation],
        scoreable: false,
        sandbox_profile: nil
      },
      %Fixture{
        id: "elixir-ex-003",
        category: :exunit,
        difficulty: :medium,
        prompt: """
        Implement `RateLimiter.new(limit)` and `RateLimiter.check(limiter)` →
        `{:ok, limiter}` or `{:error, :rate_limited}`. Then write ExUnit tests
        using `setup/1` covering: under limit, exactly at limit, over limit.
        """,
        test_code: nil,
        tags: [:exunit, :setup, :testing_patterns],
        scoreable: false,
        sandbox_profile: nil
      }
    ]
  end

  defp otp do
    [
      %Fixture{
        id: "elixir-otp-001",
        category: :otp,
        difficulty: :easy,
        prompt: """
        Implement `Processor.run/1` that squares a list of integers in parallel
        using `Task.async_stream/3` with `max_concurrency: 4`. Return in any order.
        """,
        test_code: """
        defmodule ProcessorTest do
          use ExUnit.Case
          test "squares" do assert Enum.sort(Processor.run([1, 2, 3, 4, 5])) == [1, 4, 9, 16, 25] end
          test "empty" do assert Processor.run([]) == [] end
        end
        """,
        tags: [:otp, :task, :concurrency],
        scoreable: true,
        sandbox_profile: :stdlib
      },
      %Fixture{
        id: "elixir-otp-002",
        category: :otp,
        difficulty: :easy,
        prompt: """
        Implement a `Cache` module using `Agent` with:
          - `Cache.start_link()`, `Cache.put(pid, key, value)`,
          - `Cache.get(pid, key)` → value or nil, `Cache.clear(pid)`.
        """,
        test_code: """
        defmodule CacheTest do
          use ExUnit.Case
          setup do {:ok, pid} = Cache.start_link(); %{pid: pid} end
          test "put and get", %{pid: pid} do Cache.put(pid, :x, 42); assert Cache.get(pid, :x) == 42 end
          test "missing", %{pid: pid} do assert Cache.get(pid, :nope) == nil end
          test "clear", %{pid: pid} do Cache.put(pid, :x, 1); Cache.clear(pid); assert Cache.get(pid, :x) == nil end
        end
        """,
        tags: [:otp, :agent, :state],
        scoreable: true,
        sandbox_profile: :stdlib
      },
      %Fixture{
        id: "elixir-otp-003",
        category: :otp,
        difficulty: :medium,
        prompt: """
        A config map is loaded once at startup and never mutated. Should you use a
        GenServer, Agent, ETS table, or plain module attribute? Justify each option's
        trade-offs: read performance, write safety, process dependency.
        """,
        test_code: nil,
        tags: [:otp, :design, :ets, :explanation],
        scoreable: false,
        sandbox_profile: nil
      }
    ]
  end

  defp debugging do
    [
      %Fixture{
        id: "elixir-dbg-001",
        category: :debugging,
        difficulty: :easy,
        prompt: """
        `classify(-3)` returns `:positive` instead of `:negative`. Fix the bug:

            defmodule NumberType do
              def classify(n) when n > 0, do: :positive
              def classify(n) when n > 0, do: :negative
              def classify(_n), do: :zero
            end
        """,
        test_code: """
        defmodule NumberTypeTest do
          use ExUnit.Case
          test "positive" do assert NumberType.classify(5) == :positive end
          test "negative" do assert NumberType.classify(-3) == :negative end
          test "zero" do assert NumberType.classify(0) == :zero end
        end
        """,
        tags: [:debugging, :pattern_matching, :guards],
        scoreable: true,
        sandbox_profile: :stdlib
      },
      %Fixture{
        id: "elixir-dbg-002",
        category: :debugging,
        difficulty: :easy,
        prompt: """
        `Store.get/1` crashes the GenServer. Fix it:

            defmodule Store do
              use GenServer
              def start_link(init), do: GenServer.start_link(__MODULE__, init)
              def get(pid), do: GenServer.call(pid, :get)
              def init(state), do: {:ok, state}
              def handle_call(:get, _from, state), do: {:reply, state}
            end
        """,
        test_code: """
        defmodule StoreTest do
          use ExUnit.Case
          test "get returns state" do {:ok, pid} = Store.start_link(42); assert Store.get(pid) == 42 end
          test "get map state" do {:ok, pid} = Store.start_link(%{a: 1}); assert Store.get(pid) == %{a: 1} end
        end
        """,
        tags: [:debugging, :genserver, :handle_call],
        scoreable: true,
        sandbox_profile: :stdlib
      },
      %Fixture{
        id: "elixir-dbg-003",
        category: :debugging,
        difficulty: :medium,
        prompt: """
        This overflows the stack on large lists. Rewrite `MyList.sum/1` to be tail-recursive:

            defmodule MyList do
              def sum([]), do: 0
              def sum([h | t]), do: h + sum(t)
            end
        """,
        test_code: """
        defmodule MyListTest do
          use ExUnit.Case
          test "small" do assert MyList.sum([1, 2, 3]) == 6 end
          test "large" do assert MyList.sum(Enum.to_list(1..100_000)) == 5_000_050_000 end
        end
        """,
        tags: [:debugging, :recursion, :tail_recursion],
        scoreable: true,
        sandbox_profile: :stdlib
      }
    ]
  end
end
