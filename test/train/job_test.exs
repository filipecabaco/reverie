defmodule Train.JobTest do
  use ExUnit.Case, async: true

  alias Train.{Config, Job}
  alias Ingest.Snapshot

  # Actual training requires a GPU and a downloaded model — tag :gpu.
  # These tests cover only the Elixir-side contract: validation, dispatch,
  # result parsing, and artifact verification.

  describe "Job.run/2 — validation" do
    @tag :tmp_dir
    test "returns error when config is invalid", %{tmp_dir: dir} do
      config = %Config{
        base_model: "",
        dataset_path: dir,
        output_path: Path.join(dir, "out"),
        seed: 42
      }

      assert {:error, errors} = Job.run(config, runner: :local)
      assert is_list(errors)
    end

    @tag :tmp_dir
    test "returns error when snapshot is incomplete", %{tmp_dir: dir} do
      config = valid_config(dir)
      # dataset_path exists but has no train.jsonl or snapshot.json
      assert {:error, _} = Job.run(config, runner: :local)
    end
  end

  describe "Job telemetry events" do
    @tag :tmp_dir
    test "emits :start event even when validation fails", %{tmp_dir: dir} do
      events =
        capture_telemetry([:reverie, :train, :start], fn ->
          config = %Config{
            base_model: "",
            dataset_path: dir,
            output_path: Path.join(dir, "out"),
            seed: 42
          }

          Job.run(config, runner: :local)
        end)

      assert length(events) == 1
    end
  end

  describe "Config + Snapshot integration" do
    @tag :tmp_dir
    test "a frozen snapshot satisfies verify/1 used by Job", %{tmp_dir: dir} do
      records = sample_records(3)
      {:ok, _meta} = Snapshot.freeze(dir, %{train: records}, %{dataset_id: "smoke-v0"})
      assert :ok = Snapshot.verify(dir)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp valid_config(dir) do
    %Config{
      base_model: "facebook/opt-125m",
      dataset_path: dir,
      output_path: Path.join(dir, "adapter"),
      seed: 42,
      smoke: true
    }
  end

  defp sample_records(n) do
    for i <- 1..n do
      %{
        messages: [
          %{role: "user", content: "Question #{i}"},
          %{role: "assistant", content: "Answer #{i}"}
        ],
        meta: %{id: "rec-#{i}", domain: "elixir", task_type: "implement"}
      }
    end
  end

  def telemetry_handler(_event, _measurements, _metadata, {test_pid, ref}) do
    send(test_pid, {:telemetry, ref})
  end

  defp capture_telemetry(event, fun) do
    test_pid = self()
    ref = make_ref()
    handler_id = "test-#{:erlang.phash2(ref)}"

    :telemetry.attach(handler_id, event, &__MODULE__.telemetry_handler/4, {test_pid, ref})

    fun.()

    events =
      Stream.repeatedly(fn ->
        receive do
          {:telemetry, ^ref} -> :event
        after
          50 -> :done
        end
      end)
      |> Enum.take_while(&(&1 == :event))

    :telemetry.detach(handler_id)
    events
  end
end
