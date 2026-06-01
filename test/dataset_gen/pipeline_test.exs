defmodule DatasetGen.PipelineTest do
  use ExUnit.Case, async: false

  alias DatasetGen.{Checkpoint, Config, Output, Pipeline, SandboxPool, TaskSpec}

  # ---------------------------------------------------------------------------
  # Stubs
  # ---------------------------------------------------------------------------

  defmodule OkTeacher do
    @behaviour DatasetGen.Teacher
    @impl true
    def generate(spec, _brief, _opts) do
      {:ok,
       %{
         instruction: "Implement #{spec.topic} in Elixir with proper OTP patterns.",
         answer: "Here is a well-structured implementation using GenServer.",
         code: "defmodule #{Macro.camelize(spec.topic)} do\n  use GenServer\nend",
         test_code: nil
       }}
    end

    @impl true
    def repair(_c, _e, _o), do: {:error, :no_repair}
  end

  defmodule PassSandbox do
    def validate(_code, _test_code) do
      {:ok, %{compiled: true, tests_passed: nil, output: ""}}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  @moduletag :tmp_dir

  defp config(out_path) do
    %Config{
      domain: :elixir,
      teacher: OkTeacher,
      target_count: 5,
      out_path: out_path,
      brief_policy: :none,
      generation_concurrency: 2,
      sandbox_slots: 2,
      max_repairs: 0
    }
  end

  defp spec(topic) do
    %TaskSpec{domain: :elixir, task_type: :implement, topic: topic}
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  test "pipeline keeps a valid candidate and writes it to the output file", %{tmp_dir: dir} do
    out = Path.join(dir, "out.jsonl")
    cfg = config(out)

    {:ok, pool} = SandboxPool.start_link(slots: 2)

    {:ok, _} =
      Pipeline.start_link(
        cfg: cfg,
        name: :test_pipeline_1,
        sandbox_pool: pool,
        sandbox: PassSandbox
      )

    Pipeline.push(:test_pipeline_1, [spec("Counter")])

    # Wait for the batch to flush (batch_timeout is 5s, so poll shorter)
    assert_output_written(out, 1, 6_000)

    assert Output.count(out) == 1
    [candidate] = out |> Output.read_all() |> Enum.to_list()
    assert candidate["meta"]["domain"] == "elixir"
    assert candidate["meta"]["compiled"] == true
  end

  test "pipeline processes multiple specs and outputs all kept candidates", %{tmp_dir: dir} do
    out = Path.join(dir, "multi.jsonl")
    cfg = config(out)
    {:ok, pool} = SandboxPool.start_link(slots: 2)

    {:ok, _} =
      Pipeline.start_link(
        cfg: cfg,
        name: :test_pipeline_2,
        sandbox_pool: pool,
        sandbox: PassSandbox
      )

    specs = Enum.map(["Counter", "Stack", "Queue"], &spec/1)
    Pipeline.push(:test_pipeline_2, specs)

    assert_output_written(out, 3, 8_000)
    assert Output.count(out) == 3
  end

  test "sandbox pool limits concurrent sandbox calls", %{tmp_dir: dir} do
    out = Path.join(dir, "pool.jsonl")
    cfg = %{config(out) | generation_concurrency: 4, sandbox_slots: 1}

    {:ok, pool} = SandboxPool.start_link(slots: 1)

    {:ok, _} =
      Pipeline.start_link(
        cfg: cfg,
        name: :test_pipeline_3,
        sandbox_pool: pool,
        sandbox: PassSandbox
      )

    specs = Enum.map(["A", "B", "C", "D"], &spec/1)
    Pipeline.push(:test_pipeline_3, specs)

    assert_output_written(out, 4, 10_000)

    # All 4 should complete despite only 1 sandbox slot
    assert Output.count(out) == 4
  end

  test "checkpoint tracks seen ids across runs", %{tmp_dir: dir} do
    ckpt_path = Path.join(dir, "ckpt.json")

    {:ok, initial} = Checkpoint.load(ckpt_path)
    assert Checkpoint.seen_ids(initial) |> MapSet.size() == 0

    state = initial |> Checkpoint.mark_seen("abc", :keep) |> Checkpoint.mark_seen("def", :discard)
    Checkpoint.save(ckpt_path, state)

    {:ok, reloaded} = Checkpoint.load(ckpt_path)
    assert Checkpoint.seen?(reloaded, "abc")
    assert Checkpoint.seen?(reloaded, "def")
    refute Checkpoint.seen?(reloaded, "ghi")
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp assert_output_written(path, expected_count, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    Stream.iterate(0, &(&1 + 1))
    |> Enum.reduce_while(:waiting, fn _, _ ->
      count = Output.count(path)

      cond do
        count >= expected_count ->
          {:halt, :done}

        System.monotonic_time(:millisecond) > deadline ->
          {:halt, :timeout}

        true ->
          Process.sleep(100)
          {:cont, :waiting}
      end
    end)
    |> case do
      :done ->
        :ok

      :timeout ->
        flunk(
          "Expected #{expected_count} candidates in #{path} within #{timeout_ms}ms, got #{Output.count(path)}"
        )
    end
  end
end
