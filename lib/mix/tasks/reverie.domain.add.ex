defmodule Mix.Tasks.Reverie.Domain.Add do
  use Mix.Task

  @shortdoc "Scaffold a new domain and register it"

  @moduledoc """
  Creates all the boilerplate for a new domain and registers it
  in both registries. No manual file editing required.

  What gets created:
    lib/domains/<name>.ex                              Domain config + generation config
    lib/evaluate/benchmark/fixtures/<name>.ex          Benchmark fixtures module

  What gets patched automatically:
    lib/domains/registry.ex                            Adds the domain to @registry
    lib/evaluate/benchmark/fixtures.ex                 Adds the domain to @registry

  ## Usage

      mix reverie.domain.add --name graphql
      mix reverie.domain.add --name supabase --target-pairs 2000

  ## Options

      --name           Domain name, lowercase (required)
      --target-pairs   Target training pairs. Default: 3000
      --expiry-days    Brief expiry in days. Default: 90
  """

  @switches [name: :string, target_pairs: :integer, expiry_days: :integer]
  @defaults [target_pairs: 3_000, expiry_days: 90]

  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: @switches)
    opts = Keyword.merge(@defaults, opts)

    name =
      opts[:name] ||
        Mix.raise("--name is required. Example: mix reverie.domain.add --name graphql")

    unless Regex.match?(~r/^[a-z][a-z0-9_]*$/, name) do
      Mix.raise("--name must be lowercase letters, digits, or underscores (got: #{name})")
    end

    mod_name = Macro.camelize(name)

    Mix.shell().info("Adding domain :#{name}...\n")

    write_domain_module(name, mod_name, opts)
    write_fixtures_module(name, mod_name)
    register_domain(name, mod_name)

    Mix.shell().info("""

    ✓ Domain :#{name} created and registered.

    Next steps:
      1. Edit lib/domains/#{name}.ex                        — task_weights, quality opts, etc.
      2. Edit lib/evaluate/benchmark/fixtures/#{name}.ex    — add real benchmark prompts
      3. Run: mix reverie.domain --show #{name}
    """)
  end

  # ---------------------------------------------------------------------------
  # File generation
  # ---------------------------------------------------------------------------

  defp write_domain_module(name, mod_name, opts) do
    path = "lib/domains/#{name}.ex"

    if File.exists?(path) do
      Mix.shell().info("  exists   #{path} (not overwritten)")
    else
      File.write!(path, domain_template(name, mod_name, opts))
      Mix.shell().info("  created  #{path}")
    end
  end

  defp write_fixtures_module(name, mod_name) do
    path = "lib/evaluate/benchmark/fixtures/#{name}.ex"

    if File.exists?(path) do
      Mix.shell().info("  exists   #{path} (not overwritten)")
    else
      File.write!(path, fixtures_template(name, mod_name))
      Mix.shell().info("  created  #{path}")
    end
  end

  # ---------------------------------------------------------------------------
  # Registry — append to priv/domains.exs (the single source of truth)
  # ---------------------------------------------------------------------------

  @domains_file "priv/domains.exs"

  defp register_domain(name, mod_name) do
    {entries, _} = Code.eval_file(@domains_file)
    key = String.to_atom(name)
    domain_mod = Module.concat([Domains, mod_name])
    fixtures_mod = Module.concat([Evaluate, Benchmark, Fixtures, mod_name])

    existing = Enum.find(entries, &(&1.key == key))

    cond do
      # Already fully registered — nothing to do
      existing != nil and existing.domain_module != nil ->
        Mix.shell().info("  skipped  #{@domains_file} (already fully registered)")

      # Entry exists but domain_module was nil — fill it in
      existing != nil ->
        updated =
          Enum.map(entries, fn e ->
            if e.key == key,
              do: %{e | domain_module: domain_mod, fixtures_module: fixtures_mod},
              else: e
          end)

        File.write!(@domains_file, serialize(updated))
        Mix.shell().info("  updated  #{@domains_file} (set domain_module)")

      # New domain — append
      true ->
        new_entry = %{
          key: key,
          name: mod_name,
          domain_module: domain_mod,
          fixtures_module: fixtures_mod
        }

        File.write!(@domains_file, serialize(entries ++ [new_entry]))
        Mix.shell().info("  updated  #{@domains_file}")
    end
  end

  defp serialize(entries) do
    header = """
    # Domain registry — edit this file to add or remove domains.
    # Run `mix reverie.domain.add --name <name>` to scaffold a new domain.

    [
    """

    body =
      Enum.map_join(entries, ",\n", fn e ->
        """
          %{
            key: :#{e.key},
            name: "#{e.name}",
            domain_module: #{inspect(e.domain_module)},
            fixtures_module: #{inspect(e.fixtures_module)}
          }\
        """
      end)

    header <> body <> "\n]\n"
  end

  # ---------------------------------------------------------------------------
  # Templates
  # ---------------------------------------------------------------------------

  defp domain_template(name, mod_name, opts) do
    """
    defmodule Domains.#{mod_name} do
      @behaviour Domains.Domain

      @impl true
      def domain, do: :#{name}

      @impl true
      def name, do: "#{Macro.camelize(name)}"

      @impl true
      def config do
        %{
          domain: :#{name},
          corpus_path: "data/#{name}/corpus.db",
          corpus_version: "#{name}-corpus-v1",
          source_policy: :official_and_reviewed_repos,
          target_pairs: #{opts[:target_pairs]},
          requires_retrieval: true,
          task_weights: %{
            # TODO: adjust weights to match this domain's task distribution
            implement: 0.30,
            debug: 0.25,
            refactor: 0.15,
            test: 0.20,
            explain: 0.05,
            review: 0.05
          },
          sandbox_profiles: [],
          brief_expiry_days: #{opts[:expiry_days]},
          split_ratios: %{train: 0.75, validation: 0.10, test: 0.10, regression: 0.05},
          quality: [require_compiled: false, min_answer_bytes: 50]
        }
      end

      @impl true
      def sources do
        %{
          # Declare what to fetch when running `mix reverie.corpus.build --domain #{name}`.
          # All keys are optional — include only what applies to this domain.
          #
          # hex_packages: [
          #   %{package: "my_package"},
          #   %{package: "other_package", version: "1.2.3"}
          # ],
          # repos: [
          #   %{owner: "org", repo: "repo", branch: "main"}
          # ],
          # releases: [
          #   %{owner: "org", repo: "repo", max_releases: 10}
          # ]
        }
      end

      @impl true
      def generation_config(opts \\\\ []) do
        cfg = config()

        struct(DatasetGen.Config, [
          domain: :#{name},
          teacher: Keyword.get(opts, :teacher, DatasetGen.Teacher.Claude),
          target_count: Keyword.get(opts, :target_count, cfg.target_pairs),
          out_path: Keyword.get(opts, :out_path, "data/#{name}/generated/candidates.jsonl"),
          task_weights: cfg.task_weights,
          sandbox_slots: Keyword.get(opts, :sandbox_slots, 2),
          generation_concurrency: Keyword.get(opts, :generation_concurrency, 8),
          brief_policy: Keyword.get(opts, :brief_policy, :verified_only),
          max_repairs: Keyword.get(opts, :max_repairs, 0),
          permitted_sandbox_profiles: cfg.sandbox_profiles
        ])
      end
    end
    """
  end

  defp fixtures_template(name, mod_name) do
    """
    defmodule Evaluate.Benchmark.Fixtures.#{mod_name} do
      @behaviour Evaluate.Benchmark.Domain

      alias Evaluate.Benchmark.Fixture

      @impl true
      def name, do: "#{Macro.camelize(name)}"

      @impl true
      def categories do
        # TODO: define the categories relevant to this domain
        [:concepts, :implementation, :debugging]
      end

      @impl true
      def fixtures do
        [
          %Fixture{
            id: "#{name}-concepts-001",
            category: :concepts,
            difficulty: :easy,
            prompt: \"\"\"
            TODO: Write a benchmark prompt for :#{name} here.
            This should test a fundamental concept of the domain.
            \"\"\",
            test_code: nil,
            tags: [:#{name}, :concepts],
            scoreable: false,
            sandbox_profile: nil
          }
          # TODO: add more fixtures covering each category
        ]
      end
    end
    """
  end
end
