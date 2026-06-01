defmodule Mix.Tasks.Reverie.Domain do
  use Mix.Task

  @shortdoc "List and inspect registered domains"

  @moduledoc """
  List all registered domains and inspect their configuration.

  ## Usage

      mix reverie.domain                      # list all domains
      mix reverie.domain --show elixir        # show full config for a domain
      mix reverie.domain --fixtures postgres  # list benchmark fixtures for a domain

  ## Options

      --show      Show full config for a domain
      --fixtures  List benchmark fixtures for a domain
  """

  @switches [show: :string, fixtures: :string]

  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv, strict: @switches)

    cond do
      domain = opts[:show] -> show_domain(Mix.Tasks.Reverie.Helpers.resolve_domain(domain))
      domain = opts[:fixtures] -> list_fixtures(Mix.Tasks.Reverie.Helpers.resolve_domain(domain))
      true -> list_domains()
    end
  end

  defp list_domains do
    {entries, _} = Code.eval_file("priv/domains.exs")
    Mix.shell().info("Registered domains (#{length(entries)}):\n")

    for entry <- entries do
      domain = entry.key
      has_module = entry.domain_module != nil
      status = if has_module, do: "✓", else: "–"

      fixture_count = Evaluate.Benchmark.Fixtures.for_domain(domain) |> length()
      scoreable = Evaluate.Benchmark.Fixtures.for_domain(domain) |> Enum.count(& &1.scoreable)
      categories = Evaluate.Benchmark.Fixtures.categories(domain) |> Enum.join(", ")

      Mix.shell().info("  #{status} :#{domain}  (#{entry.name})")
      Mix.shell().info("    fixtures   #{fixture_count} total, #{scoreable} sandbox-scoreable")
      Mix.shell().info("    categories #{categories}")

      if has_module do
        cfg = Domains.Registry.config(domain)

        Mix.shell().info(
          "    target     #{cfg.target_pairs} pairs  sandbox: #{inspect(cfg.sandbox_profiles)}"
        )
      else
        Mix.shell().info(
          "    pipeline   not configured yet  →  mix reverie.domain.add --name #{domain}"
        )
      end

      Mix.shell().info("")
    end

    Mix.shell().info("✓ = pipeline ready    – = fixtures only")
    Mix.shell().info("Add a domain: mix reverie.domain.add --name <name>")
  end

  defp show_domain(domain) do
    cfg = Domains.Registry.config(domain)
    gen_cfg = Domains.Registry.generation_config(domain)

    Mix.shell().info("Domain: :#{domain}  (#{Domains.Registry.name(domain)})\n")
    Mix.shell().info("Config:")

    cfg
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.each(fn {k, v} ->
      Mix.shell().info("  #{String.pad_trailing(to_string(k), 22)} #{inspect(v)}")
    end)

    Mix.shell().info("\nGeneration config:")
    Mix.shell().info("  teacher            #{gen_cfg.teacher}")
    Mix.shell().info("  target_count       #{gen_cfg.target_count}")
    Mix.shell().info("  concurrency        #{gen_cfg.generation_concurrency}")
    Mix.shell().info("  sandbox_slots      #{gen_cfg.sandbox_slots}")
    Mix.shell().info("  brief_policy       #{gen_cfg.brief_policy}")
    Mix.shell().info("  max_repairs        #{gen_cfg.max_repairs}")
    Mix.shell().info("  out_path           #{gen_cfg.out_path}")
  end

  defp list_fixtures(domain) do
    fixtures = Evaluate.Benchmark.Fixtures.for_domain(domain)
    Mix.shell().info("Fixtures for :#{domain} (#{length(fixtures)} total):\n")

    fixtures
    |> Enum.group_by(& &1.category)
    |> Enum.sort_by(fn {cat, _} -> cat end)
    |> Enum.each(fn {category, group} ->
      Mix.shell().info("  #{category} (#{length(group)})")

      Enum.each(group, fn f ->
        scoreable = if f.scoreable, do: "✓", else: "–"
        Mix.shell().info("    #{scoreable} #{f.id}  [#{f.difficulty}]")
      end)
    end)
  end
end
