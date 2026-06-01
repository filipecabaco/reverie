defmodule DatasetGen.GeneratorTest do
  use ExUnit.Case, async: true

  alias DatasetGen.{Config, Generator, TaskSpec}

  # ---------------------------------------------------------------------------
  # Stub teacher — returns a canned valid response
  # ---------------------------------------------------------------------------

  defmodule StubTeacher do
    @behaviour DatasetGen.Teacher

    @impl true
    def generate(_spec, _brief, opts) do
      response = Keyword.get(opts, :response, default_response())
      {:ok, response}
    end

    @impl true
    def repair(_candidate, _error, opts) do
      response = Keyword.get(opts, :repair_response, default_response())
      {:ok, response}
    end

    defp default_response do
      %{
        instruction: "Implement `Counter.increment/1` using a GenServer.",
        answer:
          "Here is the implementation:\n```elixir\ndef increment(pid), do: GenServer.cast(pid, :increment)\n```",
        code:
          "defmodule Counter do\n  use GenServer\n  def increment(pid), do: GenServer.cast(pid, :increment)\n  def handle_cast(:increment, n), do: {:noreply, n + 1}\nend",
        test_code: nil
      }
    end
  end

  defmodule FailingTeacher do
    @behaviour DatasetGen.Teacher

    @impl true
    def generate(_spec, _brief, _opts), do: {:error, :api_unavailable}

    @impl true
    def repair(_candidate, _error, _opts), do: {:error, :api_unavailable}
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
          teacher: StubTeacher,
          target_count: 10,
          out_path: "/tmp/test_gen",
          brief_policy: :none
        ],
        overrides
      )
    )
  end

  defp spec(overrides \\ []) do
    struct(
      TaskSpec,
      Keyword.merge(
        [
          domain: :elixir,
          task_type: :implement,
          topic: "GenServer"
        ],
        overrides
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "Generator.generate/3 — happy path" do
    test "returns a candidate with messages and meta" do
      assert {:ok, candidate} = Generator.generate(spec(), config())

      assert [%{role: "user"}, %{role: "assistant"}] = candidate.messages
      assert candidate.meta.domain == :elixir
      assert candidate.meta.task_type == :implement
      assert candidate.meta.topic == "GenServer"
      assert candidate.meta.source_kind == "synthetic_grounded"
    end

    test "candidate id is a sha256 hex derived from instruction + answer" do
      {:ok, candidate} = Generator.generate(spec(), config())
      assert String.match?(candidate.meta.id, ~r/^[0-9a-f]{64}$/)
    end

    test "candidate carries code and test_code from parsed output" do
      {:ok, candidate} = Generator.generate(spec(), config())
      assert is_binary(candidate.meta.code)
      assert is_nil(candidate.meta.test_code)
    end

    test "brief_id is nil when brief_policy is :none" do
      {:ok, candidate} = Generator.generate(spec(), config(brief_policy: :none))
      assert is_nil(candidate.meta.brief_id)
    end

    test "generated_at is an ISO8601 timestamp" do
      {:ok, candidate} = Generator.generate(spec(), config())
      assert {:ok, _, _} = DateTime.from_iso8601(candidate.meta.generated_at)
    end
  end

  describe "Generator.generate/3 — teacher failures" do
    test "propagates teacher errors" do
      assert {:error, :api_unavailable} =
               Generator.generate(spec(), config(teacher: FailingTeacher))
    end
  end

  describe "Generator.generate/3 — parser validation" do
    test "returns error when teacher output fails parser validation" do
      bad_teacher_module =
        define_bad_teacher(%{instruction: "", answer: "x", code: nil, test_code: nil})

      assert {:error, {:empty_field, :instruction}} =
               Generator.generate(spec(), config(teacher: bad_teacher_module))
    end

    test "returns error when teacher omits instruction" do
      bad_teacher_module = define_bad_teacher(%{answer: "x", code: nil, test_code: nil})

      assert {:error, {:missing_field, :instruction}} =
               Generator.generate(spec(), config(teacher: bad_teacher_module))
    end
  end

  # Dynamically define a teacher that returns a fixed bad response.
  # We use a unique module name per test via Process.info.
  defp define_bad_teacher(response) do
    mod = :"BadTeacher#{:erlang.unique_integer([:positive])}"

    Module.create(
      mod,
      quote do
        @behaviour DatasetGen.Teacher
        @impl true
        def generate(_spec, _brief, _opts), do: {:ok, unquote(Macro.escape(response))}
        @impl true
        def repair(_c, _e, _opts), do: {:ok, unquote(Macro.escape(response))}
      end,
      __ENV__
    )

    mod
  end
end
