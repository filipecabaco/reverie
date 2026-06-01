defmodule Train.BakeoffTest do
  use ExUnit.Case, async: true

  alias Train.Bakeoff
  alias Train.Bakeoff.{Compatibility, Report}
  alias Train.ModelCandidate

  # ---------------------------------------------------------------------------
  # ModelCandidate
  # ---------------------------------------------------------------------------

  describe "ModelCandidate.shortlist/0" do
    test "returns at least two candidates" do
      assert length(ModelCandidate.shortlist()) >= 2
    end

    test "all candidates have required fields" do
      for c <- ModelCandidate.shortlist() do
        assert is_binary(c.id), "#{c.name}: id must be a string"
        assert is_binary(c.name), "#{c.id}: name must be a string"
        assert is_number(c.params_b), "#{c.id}: params_b must be a number"
        assert is_boolean(c.commercial_ok), "#{c.id}: commercial_ok must be boolean"
        assert is_boolean(c.qlora_compatible), "#{c.id}: qlora_compatible must be boolean"
      end
    end

    test "all shortlisted candidates are eligible" do
      for c <- ModelCandidate.shortlist() do
        assert ModelCandidate.eligible?(c), "#{c.id} should be eligible"
      end
    end
  end

  describe "ModelCandidate.eligible?/1" do
    test "returns true when commercial_ok and qlora_compatible" do
      c = %ModelCandidate{
        id: "org/model",
        name: "model",
        params_b: 7.0,
        license: :apache2,
        commercial_ok: true,
        qlora_compatible: true
      }

      assert ModelCandidate.eligible?(c)
    end

    test "returns false when commercial_ok is false" do
      c = %ModelCandidate{
        id: "org/model",
        name: "model",
        params_b: 7.0,
        license: :proprietary,
        commercial_ok: false,
        qlora_compatible: true
      }

      refute ModelCandidate.eligible?(c)
    end
  end

  # ---------------------------------------------------------------------------
  # Compatibility checklist
  # ---------------------------------------------------------------------------

  describe "Compatibility" do
    test "new/0 starts all gates as :pending" do
      checklist = Compatibility.new()
      assert Enum.all?(Map.values(checklist), &(&1.status == :pending))
    end

    test "passed?/1 is false when gates are pending" do
      refute Compatibility.passed?(Compatibility.new())
    end

    test "passed?/1 is true when all non-skipped gates pass" do
      checklist =
        Compatibility.gates()
        |> Enum.reduce(Compatibility.new(), fn gate, acc ->
          Compatibility.mark(acc, gate, :pass)
        end)

      assert Compatibility.passed?(checklist)
    end

    test "failures/1 returns only failed gates" do
      checklist =
        Compatibility.new()
        |> Compatibility.mark(:base_loads, :pass)
        |> Compatibility.mark(:adapter_unmerged, :fail, "OOM on load")

      assert Compatibility.failures(checklist) == [:adapter_unmerged]
    end

    test "pending/1 returns gates not yet evaluated" do
      checklist = Compatibility.new() |> Compatibility.mark(:base_loads, :pass)
      pending = Compatibility.pending(checklist)
      refute :base_loads in pending
      assert length(pending) == length(Compatibility.gates()) - 1
    end

    test "mark/4 records note" do
      checklist = Compatibility.new() |> Compatibility.mark(:base_loads, :fail, "timeout")
      assert checklist[:base_loads].note == "timeout"
    end

    test "summary/2 is a non-empty string containing the candidate name" do
      c = hd(ModelCandidate.shortlist())
      summary = Compatibility.summary(Compatibility.new(), c)
      assert String.contains?(summary, c.name)
    end
  end

  # ---------------------------------------------------------------------------
  # Bakeoff.Report
  # ---------------------------------------------------------------------------

  describe "Bakeoff.Report" do
    test "build/3 ranks candidates by weighted score descending" do
      candidates = ModelCandidate.shortlist()

      results =
        candidates
        |> Enum.with_index()
        |> Enum.map(fn {c, i} ->
          benchmark = fake_benchmark(compile_rate: 90.0 - i * 10, test_pass_rate: 80.0 - i * 10)
          {c, benchmark}
        end)

      report = Report.build(:elixir, results)

      scores = Enum.map(report.scores, & &1.weighted_score)
      assert scores == Enum.sort(scores, :desc)
    end

    test "build/3 sets recommendation to the highest-scoring eligible candidate" do
      [c1, c2 | _] = ModelCandidate.shortlist()

      results = [
        {c1, fake_benchmark(compile_rate: 50.0, test_pass_rate: 40.0)},
        {c2, fake_benchmark(compile_rate: 90.0, test_pass_rate: 85.0)}
      ]

      report = Report.build(:elixir, results)
      assert report.recommendation.id == c2.id
    end

    test "build/3 returns nil recommendation when no candidate is eligible" do
      ineligible = %ModelCandidate{
        id: "org/restricted",
        name: "restricted",
        params_b: 7.0,
        license: :proprietary,
        commercial_ok: false,
        qlora_compatible: true
      }

      report = Report.build(:elixir, [{ineligible, fake_benchmark()}])
      assert report.recommendation == nil
    end

    test "summary/1 is a non-empty string with domain and rates" do
      [c | _] = ModelCandidate.shortlist()
      report = Report.build(:elixir, [{c, fake_benchmark()}])
      summary = Report.summary(report)
      assert String.contains?(summary, "elixir")
      assert String.contains?(summary, "%")
    end

    test "to_json/1 produces valid JSON with all candidate ids" do
      candidates = ModelCandidate.shortlist()
      results = Enum.map(candidates, &{&1, fake_benchmark()})
      report = Report.build(:elixir, results)

      assert {:ok, json} = Report.to_json(report)
      assert {:ok, parsed} = Jason.decode(json)
      scored_ids = Enum.map(parsed["scores"], & &1["candidate_id"])

      for c <- candidates do
        assert c.id in scored_ids
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Bakeoff.save/2 and record_selection/2
  # ---------------------------------------------------------------------------

  describe "Bakeoff.save/2" do
    @tag :tmp_dir
    test "writes bakeoff_report.json and compatibility placeholders", %{tmp_dir: dir} do
      [c | _] = ModelCandidate.shortlist()
      report = Report.build(:elixir, [{c, fake_benchmark()}])

      assert :ok = Bakeoff.save(report, dir)
      assert File.exists?(Path.join(dir, "bakeoff_report.json"))

      compat_dirs = dir |> Path.join("compatibility") |> File.ls!()
      assert length(compat_dirs) == length(report.scores)
    end
  end

  describe "Bakeoff.record_selection/2 and load_selection/1" do
    @tag :tmp_dir
    test "round-trips the selected candidate", %{tmp_dir: dir} do
      [c | _] = ModelCandidate.shortlist()
      Bakeoff.record_selection(c, dir)

      assert {:ok, loaded} = Bakeoff.load_selection(dir)
      assert loaded["id"] == c.id
      assert loaded["name"] == c.name
    end

    @tag :tmp_dir
    test "load_selection returns :not_found when nothing recorded", %{tmp_dir: dir} do
      assert {:error, :not_found} = Bakeoff.load_selection(dir)
    end
  end

  # ---------------------------------------------------------------------------
  # Bakeoff.run/3 integration (stub responder)
  # ---------------------------------------------------------------------------

  describe "Bakeoff.run/3" do
    test "runs the benchmark for each eligible candidate and returns a report" do
      candidates = ModelCandidate.shortlist()

      factory = fn _candidate ->
        fn _prompt -> "defmodule Stub do end" end
      end

      report = Bakeoff.run(candidates, factory, domain: :elixir)

      assert %Report{} = report
      assert length(report.scores) == length(Enum.filter(candidates, &ModelCandidate.eligible?/1))
    end

    test "skips ineligible candidates by default" do
      ineligible = %ModelCandidate{
        id: "org/no",
        name: "no",
        params_b: 7.0,
        license: :proprietary,
        commercial_ok: false,
        qlora_compatible: true
      }

      factory = fn _c -> fn _p -> "" end end
      report = Bakeoff.run([ineligible], factory, domain: :elixir)
      assert report.scores == []
    end

    test "concurrency option returns the same candidate set as sequential" do
      candidates = ModelCandidate.shortlist()
      factory = fn _candidate -> fn _prompt -> "defmodule Stub do end" end end

      sequential = Bakeoff.run(candidates, factory, domain: :elixir, concurrency: 1)

      parallel =
        Bakeoff.run(candidates, factory, domain: :elixir, concurrency: length(candidates))

      sequential_ids = MapSet.new(sequential.scores, & &1.candidate.id)
      parallel_ids = MapSet.new(parallel.scores, & &1.candidate.id)

      assert parallel_ids == sequential_ids
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp fake_benchmark(opts \\ []) do
    compile_rate = Keyword.get(opts, :compile_rate, 75.0)
    test_pass_rate = Keyword.get(opts, :test_pass_rate, 60.0)

    %Evaluate.Benchmark.Report{
      domain: :elixir,
      total: 10,
      scoreable_count: 8,
      compile_rate: compile_rate,
      test_pass_rate: test_pass_rate,
      by_category: %{},
      scores: []
    }
  end
end
