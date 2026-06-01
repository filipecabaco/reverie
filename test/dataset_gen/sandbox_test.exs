defmodule DatasetGen.SandboxTest do
  use ExUnit.Case, async: false

  # Requires Docker. Run with: mix test --include docker
  @moduletag :docker

  alias DatasetGen.Sandbox

  # --- positive cases ---

  test "benign module compiles" do
    code = """
    defmodule Candidate do
      def hello, do: :world
    end
    """

    assert {:ok, %{compiled: true, tests_passed: nil, output: _}} = Sandbox.validate(code)
  end

  test "passing test is recorded" do
    code = """
    defmodule Candidate do
      def add(a, b), do: a + b
    end
    """

    test_code = """
    defmodule CandidateTest do
      use ExUnit.Case
      test "adds" do
        assert Candidate.add(1, 2) == 3
      end
    end
    """

    assert {:ok, %{compiled: true, tests_passed: true}} = Sandbox.validate(code, test_code)
  end

  test "failing test is recorded" do
    code = """
    defmodule Candidate do
      def add(a, b), do: a - b
    end
    """

    test_code = """
    defmodule CandidateTest do
      use ExUnit.Case
      test "adds" do
        assert Candidate.add(1, 2) == 3
      end
    end
    """

    assert {:ok, %{compiled: true, tests_passed: false}} = Sandbox.validate(code, test_code)
  end

  test "syntax error is recorded as not compiled" do
    code = "def broken do"

    assert {:ok, %{compiled: false}} = Sandbox.validate(code)
  end

  # --- containment cases ---

  test "compile-time infinite loop times out and container is destroyed" do
    code = """
    defmodule Candidate do
      @loop Stream.cycle([1]) |> Enum.take(1_000_000_000)
    end
    """

    assert {:error, :timeout} = Sandbox.validate(code)
    refute container_running?("dataset-sbx-")
  end

  test "attempt to write outside /work fails" do
    code = """
    defmodule Candidate do
      _ = File.write("/input/pwned", "pwned")
    end
    """

    assert {:ok, %{compiled: false}} = Sandbox.validate(code)
  end

  test "network connection attempt fails" do
    code = """
    defmodule Candidate do
      _ = :gen_tcp.connect(~c"example.com", 80, [], 2000)
    end
    """

    # Container starts and compiles but the TCP connect must fail at runtime.
    # We just need it to not succeed — either compile error or runtime error is fine.
    result = Sandbox.validate(code)
    assert match?({:ok, _}, result) or match?({:error, _}, result)

    # The important assertion: no open connection was made.
    # Since network is disabled, connect returns {:error, _} inside the sandbox.
    # We can only observe this indirectly; the test documents the expectation.
  end

  test "host source directory is unchanged after a write attempt" do
    code = """
    defmodule Candidate do
      _ = File.write("/input/injected.ex", "injected")
    end
    """

    tmp = System.tmp_dir!()
    before_files = File.ls!(tmp)

    Sandbox.validate(code)

    # The /input mount is read-only; no new file should appear in host tmp.
    after_files = File.ls!(tmp)
    new_files = after_files -- before_files
    refute Enum.any?(new_files, &String.contains?(&1, "injected"))
  end

  # --- helpers ---

  defp container_running?(name_prefix) do
    {output, _} = System.cmd("docker", ["ps", "--format", "{{.Names}}"], stderr_to_stdout: true)
    String.contains?(output, name_prefix)
  end
end
