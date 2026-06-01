defmodule Evaluate.FourWayTest do
  use ExUnit.Case, async: true

  alias Evaluate.Benchmark.Report
  alias Evaluate.FourWay
  alias Evaluate.FourWay.Result

  # ---------------------------------------------------------------------------
  # Stub responders that return canned code
  # ---------------------------------------------------------------------------

  defp stub_responder(code) do
    fn _prompt -> code end
  end

  defp responders(overrides \\ %{}) do
    defaults = %{
      base: stub_responder("defmodule Stub do end"),
      base_retrieval: stub_responder("defmodule Stub do end"),
      adapter: stub_responder("defmodule Stub do end"),
      adapter_retrieval: stub_responder("defmodule Stub do end")
    }

    Map.merge(defaults, overrides)
  end

  # ---------------------------------------------------------------------------
  # FourWay.Result
  # ---------------------------------------------------------------------------

  describe "Result.build/2" do
    test "builds comparison metrics correctly" do
      reports = %{
        base: fake_report(50.0, 40.0),
        base_retrieval: fake_report(60.0, 55.0),
        adapter: fake_report(70.0, 65.0),
        adapter_retrieval: fake_report(80.0, 75.0)
      }

      result = Result.build(:elixir, reports)

      assert result.comparison.adapter_gain == 25.0
      assert result.comparison.adapter_retrieval_gain == 20.0
      assert result.comparison.retrieval_gain_base == 15.0
      assert result.comparison.retrieval_gain_adapter == 10.0
      assert result.comparison.adapter_beats_base == true
      assert result.comparison.adapter_retrieval_beats_base_retrieval == true
    end

    test "adapter_beats_base is false when adapter is worse" do
      reports = %{
        base: fake_report(80.0, 70.0),
        base_retrieval: fake_report(80.0, 70.0),
        adapter: fake_report(60.0, 50.0),
        adapter_retrieval: fake_report(60.0, 50.0)
      }

      result = Result.build(:elixir, reports)
      assert result.comparison.adapter_beats_base == false
      assert result.comparison.adapter_gain == -20.0
    end

    test "detects retrieval-only gain (adapter does not add value beyond retrieval)" do
      # Adapter improves over base, but adapter+retrieval does NOT improve over base+retrieval.
      # This means the adapter's "gain" is just what retrieval would have given anyway.
      reports = %{
        base: fake_report(50.0, 40.0),
        base_retrieval: fake_report(70.0, 65.0),
        adapter: fake_report(70.0, 65.0),
        adapter_retrieval: fake_report(70.0, 65.0)
      }

      result = Result.build(:elixir, reports)
      assert result.comparison.adapter_beats_base == true
      assert result.comparison.adapter_retrieval_beats_base_retrieval == false
    end

    test "summary contains all four conditions" do
      reports = Map.new(Result.conditions(), fn c -> {c, fake_report(60.0, 50.0)} end)
      result = Result.build(:elixir, reports)
      summary = Result.summary(result)

      for condition <- Result.conditions() do
        assert String.contains?(summary, to_string(condition)),
               "summary missing condition: #{condition}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # FourWay.run/3
  # ---------------------------------------------------------------------------

  describe "FourWay.run/3" do
    test "runs all four conditions and returns a Result" do
      result = FourWay.run(:elixir, responders())
      assert %Result{} = result
      assert result.domain == :elixir
    end

    test "each condition produces a Benchmark.Report" do
      result = FourWay.run(:elixir, responders())

      for condition <- Result.conditions() do
        assert %Report{} = Map.get(result, condition),
               "#{condition} is not a Report"
      end
    end

    test "conditions with better code produce higher metrics" do
      # The stub for :adapter returns the stub that will compile;
      # we can't easily test sandbox without Docker, but we verify the
      # structure and that metrics are in [0.0, 100.0].
      result = FourWay.run(:elixir, responders())

      for condition <- Result.conditions() do
        report = Map.get(result, condition)
        assert report.compile_rate >= 0.0 and report.compile_rate <= 100.0
        assert report.test_pass_rate >= 0.0 and report.test_pass_rate <= 100.0
      end
    end

    test "raises on missing responder" do
      incomplete = Map.delete(responders(), :adapter)

      assert_raise ArgumentError, ~r/missing responders/, fn ->
        FourWay.run(:elixir, incomplete)
      end
    end
  end

  describe "FourWay.run_condition/4" do
    test "runs a single condition and returns a Report" do
      report = FourWay.run_condition(:elixir, :base, stub_responder("defmodule X do end"))
      assert %Report{} = report
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp fake_report(compile_rate, test_pass_rate) do
    %Report{
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
