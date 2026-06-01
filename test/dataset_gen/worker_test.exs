defmodule DatasetGen.WorkerTest do
  use ExUnit.Case, async: true

  alias DatasetGen.{Config, TaskSpec, Worker}

  # ---------------------------------------------------------------------------
  # Stubs
  # ---------------------------------------------------------------------------

  defmodule OkTeacher do
    @behaviour DatasetGen.Teacher

    @impl true
    def generate(_spec, _brief, opts) do
      response = Keyword.get(opts, :teacher_response, default())
      {:ok, response}
    end

    @impl true
    def repair(_candidate, _error, opts) do
      response = Keyword.get(opts, :repair_response, default())
      {:ok, response}
    end

    defp default do
      %{
        instruction: "Implement Stack.new/0 and Stack.push/2.",
        answer: "Use a list internally. `new/0` returns `[]`, `push/2` prepends.",
        code: "defmodule Stack do\n  def new, do: []\n  def push(s, i), do: [i | s]\nend",
        test_code: nil
      }
    end
  end

  defmodule FailTeacher do
    @behaviour DatasetGen.Teacher
    @impl true
    def generate(_s, _b, _o), do: {:error, :api_unavailable}
    @impl true
    def repair(_c, _e, _o), do: {:error, :api_unavailable}
  end

  defmodule BadOutputTeacher do
    @behaviour DatasetGen.Teacher
    @impl true
    def generate(_s, _b, _o),
      do: {:ok, %{instruction: "", answer: "x", code: nil, test_code: nil}}

    @impl true
    def repair(_c, _e, _o), do: {:ok, %{instruction: "", answer: "x", code: nil, test_code: nil}}
  end

  defmodule ShortAnswerTeacher do
    @behaviour DatasetGen.Teacher
    @impl true
    def generate(_s, _b, _o),
      do: {:ok, %{instruction: "What is x?", answer: "x", code: nil, test_code: nil}}

    @impl true
    def repair(_c, _e, _o),
      do: {:ok, %{instruction: "What is x?", answer: "x", code: nil, test_code: nil}}
  end

  # Sandbox stubs — a module with a validate/2 function
  defmodule PassSandbox do
    def validate(_code, test_code) do
      tests_passed = if is_nil(test_code), do: nil, else: true
      {:ok, %{compiled: true, tests_passed: tests_passed, output: ""}}
    end
  end

  defmodule FailCompileSandbox do
    def validate(_code, _test_code) do
      {:ok, %{compiled: false, tests_passed: false, output: "** (CompileError) nofile:1"}}
    end
  end

  defmodule FailTestSandbox do
    def validate(_code, _test_code) do
      {:ok, %{compiled: true, tests_passed: false, output: "1 test, 1 failure"}}
    end
  end

  defmodule TimeoutSandbox do
    def validate(_code, _test_code), do: {:error, :timeout}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp config(overrides \\ []) do
    struct(
      Config,
      Keyword.merge(
        [
          domain: :elixir,
          teacher: OkTeacher,
          target_count: 10,
          out_path: "/tmp/test_worker",
          brief_policy: :none,
          max_repairs: 0
        ],
        overrides
      )
    )
  end

  defp spec do
    %TaskSpec{domain: :elixir, task_type: :implement, topic: "Stack data structure"}
  end

  defp opts(sandbox), do: [sandbox: sandbox]

  # ---------------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------------

  describe "Worker.process/3 — happy path" do
    test "keeps a valid candidate that compiles and passes tests" do
      assert {:keep, candidate} = Worker.process(spec(), config(), opts(PassSandbox))

      assert [%{role: "user"}, %{role: "assistant"}] = candidate.messages
      assert candidate.meta.compiled == true
      assert candidate.meta.domain == :elixir
      assert candidate.meta.source_kind == "synthetic_grounded"
    end

    test "candidate id is deterministic sha256 hex" do
      {:keep, candidate} = Worker.process(spec(), config(), opts(PassSandbox))
      assert String.match?(candidate.meta.id, ~r/^[0-9a-f]{64}$/)
    end

    test "two calls with same instruction produce the same id" do
      {:keep, c1} = Worker.process(spec(), config(), opts(PassSandbox))
      {:keep, c2} = Worker.process(spec(), config(), opts(PassSandbox))
      assert c1.meta.id == c2.meta.id
    end

    test "keeps a no-code candidate without calling sandbox" do
      # ShortAnswerTeacher returns an instruction that is 10+ chars but answer < 20 chars,
      # so it's discarded by static gate. Use OkTeacher with no code.
      code_free = config(teacher: OkTeacher)

      # OkTeacher returns code — override with teacher_response to strip code
      {:keep, candidate} =
        Worker.process(spec(), code_free,
          sandbox: PassSandbox,
          teacher_response: %{
            instruction: "Explain what a stack data structure is.",
            answer:
              "A stack is a LIFO data structure where items are added and removed from the top.",
            code: nil,
            test_code: nil
          }
        )

      assert is_nil(candidate.meta.code)
      assert candidate.meta.compiled == true
      assert is_nil(candidate.meta.tests_passed)
    end

    test "generated_at is a valid ISO8601 timestamp" do
      {:keep, candidate} = Worker.process(spec(), config(), opts(PassSandbox))
      assert {:ok, _, _} = DateTime.from_iso8601(candidate.meta.generated_at)
    end
  end

  # ---------------------------------------------------------------------------
  # Pipeline failures
  # ---------------------------------------------------------------------------

  describe "Worker.process/3 — teacher failure" do
    test "discards when teacher returns an error" do
      assert {:discard, :api_unavailable} =
               Worker.process(spec(), config(teacher: FailTeacher), opts(PassSandbox))
    end
  end

  describe "Worker.process/3 — parser failure" do
    test "discards when teacher output fails parser validation" do
      assert {:discard, {:empty_field, :instruction}} =
               Worker.process(spec(), config(teacher: BadOutputTeacher), opts(PassSandbox))
    end
  end

  describe "Worker.process/3 — static policy gate" do
    test "discards when answer is too short" do
      assert {:discard, :answer_too_short} =
               Worker.process(spec(), config(teacher: ShortAnswerTeacher), opts(PassSandbox))
    end
  end

  describe "Worker.process/3 — sandbox failure" do
    test "discards on compile failure when max_repairs is 0" do
      assert {:discard, _} =
               Worker.process(spec(), config(max_repairs: 0), opts(FailCompileSandbox))
    end

    test "discards on sandbox timeout" do
      assert {:discard, :sandbox_timeout} =
               Worker.process(spec(), config(), opts(TimeoutSandbox))
    end

    test "discards on test failure when max_repairs is 0" do
      # Needs a candidate with test_code to trigger test run
      cfg = config(max_repairs: 0)

      extra = [
        sandbox: FailTestSandbox,
        teacher_response: %{
          instruction: "Implement Stack.push/2 with tests.",
          answer: "Here is the implementation and tests.",
          code: "defmodule Stack do\n  def push(s, i), do: [i | s]\nend",
          test_code:
            "defmodule StackTest do\n  use ExUnit.Case\n  test \"push\" do\n    assert Stack.push([], 1) == [1]\n  end\nend"
        }
      ]

      assert {:discard, _} = Worker.process(spec(), cfg, extra)
    end
  end

  # ---------------------------------------------------------------------------
  # Repair flow
  # ---------------------------------------------------------------------------

  describe "Worker.process/3 — repair" do
    test "keeps candidate after one successful repair" do
      # First call to generate returns bad code (compile fails);
      # repair call returns valid code (compile passes).
      dynamic_teacher = make_counting_teacher()

      cfg = config(teacher: dynamic_teacher, max_repairs: 1)

      # Sandbox: fail on first call, pass on second
      fail_then_pass = make_fail_then_pass_sandbox()

      result = Worker.process(spec(), cfg, sandbox: fail_then_pass)
      assert {:keep, candidate} = result
      assert candidate.meta.compiled == true
    end
  end

  # ---------------------------------------------------------------------------
  # Evidence gate
  # ---------------------------------------------------------------------------

  describe "Worker.process/3 — evidence gate (no brief)" do
    test "passes evidence gate when no brief is attached" do
      # brief_policy: :none means no brief is fetched and evidence gate is skipped
      assert {:keep, _} = Worker.process(spec(), config(brief_policy: :none), opts(PassSandbox))
    end
  end

  # ---------------------------------------------------------------------------
  # Dynamic teacher helpers
  # ---------------------------------------------------------------------------

  defp make_counting_teacher do
    mod = :"CountingTeacher#{:erlang.unique_integer([:positive])}"

    bad_response = %{
      instruction: "Implement Stack.push/2.",
      answer: "Here is the broken implementation.",
      code: "defmodule Stack do\n  def push(s, i), do: [i | s]\nend",
      test_code: nil
    }

    good_response = %{
      instruction: "Implement Stack.push/2.",
      answer: "Here is the correct implementation.",
      code: "defmodule Stack do\n  def push(s, i), do: [i | s]\nend",
      test_code: nil
    }

    Module.create(
      mod,
      quote do
        @behaviour DatasetGen.Teacher
        @impl true
        def generate(_s, _b, _o) do
          {:ok, unquote(Macro.escape(bad_response))}
        end

        @impl true
        def repair(_c, _e, _o) do
          {:ok, unquote(Macro.escape(good_response))}
        end
      end,
      __ENV__
    )

    mod
  end

  defp make_fail_then_pass_sandbox do
    table = :"sandbox_ftp_#{:erlang.unique_integer([:positive])}"
    :ets.new(table, [:named_table, :set, :public])
    :ets.insert(table, {:count, 0})
    mod = :"FailThenPassSandbox#{:erlang.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @table unquote(table)

        def validate(_code, _test_code) do
          [{:count, n}] = :ets.lookup(@table, :count)
          :ets.insert(@table, {:count, n + 1})

          if n == 0 do
            {:ok, %{compiled: false, tests_passed: false, output: "** (CompileError)"}}
          else
            {:ok, %{compiled: true, tests_passed: nil, output: ""}}
          end
        end
      end,
      __ENV__
    )

    mod
  end
end
