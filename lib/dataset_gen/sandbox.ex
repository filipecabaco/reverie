defmodule DatasetGen.Sandbox do
  @moduledoc """
  Compiles and optionally tests generated Elixir inside a disposable,
  network-disabled, resource-capped container. Generated code must NEVER
  be compiled in the orchestrator BEAM — Elixir compilation runs arbitrary
  code via macros, compile-time file/process/shell/network access.
  """

  @image "dataset-gen-sandbox:stdlib"
  @inner_timeout_s 30
  @outer_timeout_ms 45_000

  @type verdict :: %{
          compiled: boolean(),
          tests_passed: boolean() | nil,
          output: String.t()
        }

  @spec validate(String.t(), String.t() | nil) :: {:ok, verdict()} | {:error, :timeout | term()}
  def validate(code, test \\ nil) when is_binary(code) do
    source_dir = make_project(code, test)

    name = "dataset-sbx-" <> random_id()

    try do
      run_container(name, source_dir, not is_nil(test))
    after
      force_cleanup(name)
      File.rm_rf(source_dir)
    end
  end

  @spec image() :: String.t()
  def image, do: @image

  defp make_project(code, test) do
    dir = Path.join(System.tmp_dir!(), "dataset-src-" <> random_id())

    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, "lib/generated.ex"), code)
    File.write!(Path.join(dir, "mix.exs"), mix_exs())

    if test do
      File.mkdir_p!(Path.join(dir, "test"))
      File.write!(Path.join(dir, "test/generated_test.exs"), "ExUnit.start()\n" <> test)
    end

    set_permissions(dir)
    dir
  end

  defp set_permissions(dir) do
    File.chmod!(dir, 0o755)

    Path.wildcard(Path.join(dir, "**/*"))
    |> Enum.each(fn path ->
      mode = if File.dir?(path), do: 0o755, else: 0o644
      File.chmod!(path, mode)
    end)
  end

  defp run_container(name, source_dir, run_tests?) do
    inner =
      if run_tests?,
        do: "mix compile --warnings-as-errors && mix test",
        else: "mix compile --warnings-as-errors"

    command =
      "cp -R /input/. /work && cd /work && timeout #{@inner_timeout_s}s sh -lc '#{inner}'"

    args = [
      "run",
      "--name",
      name,
      "--rm",
      "--network",
      "none",
      "--read-only",
      "--memory",
      "512m",
      "--cpus",
      "1",
      "--pids-limit",
      "128",
      "--cap-drop",
      "ALL",
      "--security-opt",
      "no-new-privileges",
      "--user",
      "65532:65532",
      "--tmpfs",
      "/work:rw,nosuid,nodev,size=256m",
      "--tmpfs",
      "/tmp:rw,nosuid,nodev,size=64m",
      "-v",
      "#{source_dir}:/input:ro",
      @image,
      "sh",
      "-lc",
      command
    ]

    task = Task.async(fn -> System.cmd("docker", args, stderr_to_stdout: true) end)

    case Task.yield(task, @outer_timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {out, 0}} ->
        {:ok, %{compiled: true, tests_passed: run_tests? || nil, output: out}}

      {:ok, {_out, 124}} ->
        {:error, :timeout}

      {:ok, {out, _}} ->
        {:ok,
         %{
           compiled: compiled?(out),
           tests_passed: if(run_tests?, do: false, else: nil),
           output: out
         }}

      nil ->
        {:error, :timeout}
    end
  end

  defp force_cleanup(name) do
    System.cmd("docker", ["kill", name], stderr_to_stdout: true)
    System.cmd("docker", ["rm", "-f", name], stderr_to_stdout: true)
    :ok
  rescue
    _ -> :ok
  end

  defp compiled?(out) do
    not String.contains?(out, [
      "** (CompileError)",
      "** (SyntaxError)",
      "** (TokenMissingError)"
    ])
  end

  defp random_id do
    8 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp mix_exs do
    """
    defmodule Generated.MixProject do
      use Mix.Project

      def project do
        [
          app: :generated_candidate,
          version: "0.0.0",
          elixir: "~> 1.18",
          deps: []
        ]
      end
    end
    """
  end
end
