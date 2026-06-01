defmodule Mix.Tasks.Reverie.Generate do
  use Mix.Task

  @shortdoc "Generate training candidates for a domain"

  @moduledoc """
  Runs the generation pipeline for a domain and writes candidates to JSONL.

  ## Usage

      mix reverie.generate --domain elixir --count 100

  ## Options

      --domain       Domain key. Default: elixir
      --count        Target number of candidates. Default: 100
      --concurrency  Parallel teacher calls. Default: 4
      --sandbox-slots Max concurrent sandbox containers. Default: 2
      --out          Output JSONL path. Default: data/<domain>/generated/candidates.jsonl
      --data-dir     Root data directory. Default: data
      --backend      api (default, requires credits) or cli (uses claude CLI session)
      --no-sandbox   Skip sandbox validation (faster, less safe). Default: false
  """

  @switches [
    domain: :string,
    count: :integer,
    concurrency: :integer,
    sandbox_slots: :integer,
    out: :string,
    data_dir: :string,
    backend: :string,
    no_sandbox: :boolean
  ]

  @defaults [
    domain: "elixir",
    count: 100,
    concurrency: 4,
    sandbox_slots: 2,
    data_dir: "data",
    backend: "api",
    no_sandbox: false
  ]

  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    opts = Keyword.merge(@defaults, opts)

    backend = opts[:backend]
    teacher = Mix.Tasks.Reverie.Helpers.resolve_backend(backend)

    if backend == "api", do: ensure_api_key!()

    domain = Mix.Tasks.Reverie.Helpers.resolve_domain(opts[:domain])
    count = opts[:count]
    data_dir = opts[:data_dir]
    out = opts[:out] || Path.join([data_dir, to_string(domain), "generated", "candidates.jsonl"])
    sandbox_mod = if opts[:no_sandbox], do: PassthroughSandbox, else: DatasetGen.Sandbox

    File.mkdir_p!(Path.dirname(out))

    cfg = %DatasetGen.Config{
      domain: domain,
      teacher: teacher,
      target_count: count,
      out_path: out,
      generation_concurrency: opts[:concurrency],
      sandbox_slots: opts[:sandbox_slots],
      brief_policy: :verified_only,
      max_repairs: 1
    }

    Mix.shell().info("⚙  Generating #{count} candidates for :#{domain} (backend: #{backend})")
    Mix.shell().info("   Output: #{out}")

    {:ok, pool} = DatasetGen.SandboxPool.start_link(slots: cfg.sandbox_slots)

    {:ok, _} =
      DatasetGen.Pipeline.start_link(
        cfg: cfg,
        name: :"reverie_gen_#{domain}",
        sandbox_pool: pool,
        sandbox: sandbox_mod
      )

    specs = build_specs(domain, count, cfg.task_weights)
    DatasetGen.Pipeline.push(:"reverie_gen_#{domain}", specs)

    # Poll until the output file has enough candidates or we timeout
    wait_for_output(out, count, timeout_ms: 300_000)

    final_count = DatasetGen.Output.count(out)
    Mix.shell().info("✓ Done. #{final_count} candidates written to #{out}")
  end

  defp build_specs(domain, count, task_weights) do
    # topic is intentionally nil — the teacher (Claude) picks an appropriate
    # topic for each domain+task_type combination rather than us hardcoding it.
    task_weights
    |> Enum.flat_map(fn {type, weight} ->
      List.duplicate(type, round(weight * count))
    end)
    |> Enum.take(count)
    |> Enum.map(fn task_type ->
      %DatasetGen.TaskSpec{domain: domain, task_type: task_type}
    end)
  end

  defp wait_for_output(path, target, timeout_ms: timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    Stream.iterate(0, & &1)
    |> Enum.reduce_while(:waiting, fn _, _ ->
      count = DatasetGen.Output.count(path)

      cond do
        count >= target ->
          {:halt, :done}

        System.monotonic_time(:millisecond) > deadline ->
          {:halt, :timeout}

        true ->
          Mix.shell().info("  #{count}/#{target} candidates...")
          Process.sleep(5_000)
          {:cont, :waiting}
      end
    end)
  end

  defp ensure_api_key! do
    if System.get_env("ANTHROPIC_API_KEY") in [nil, ""] do
      Mix.raise("""
      ANTHROPIC_API_KEY is not set.
      Run: export $(grep -v '^#' .env | xargs)
      """)
    end
  end
end

# Used when --no-sandbox is passed — lets code through without Docker
defmodule PassthroughSandbox do
  def validate(_code, _test), do: {:ok, %{compiled: true, tests_passed: nil, output: ""}}
end
