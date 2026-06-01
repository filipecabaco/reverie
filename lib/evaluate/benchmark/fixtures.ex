defmodule Evaluate.Benchmark.Fixtures do
  @moduledoc """
  Registry of all domain fixture modules.

  The fixture registry is driven by `priv/domains.exs` — the same file
  that controls `Domains.Registry`. Adding a domain to that file makes
  its fixtures automatically available here.

  Fixtures come from two sources merged transparently:
  - **Static** — compiled modules implementing `Evaluate.Benchmark.Domain`,
    declared in `priv/domains.exs` via `:fixtures_module`.
  - **Dynamic** — fixtures generated at runtime from research briefs via
    `Evaluate.Benchmark.DynamicFixtures`. Always `scoreable: false` drafts.

  `for_domain/1` returns static ++ dynamic, with static IDs taking precedence.
  """

  alias Evaluate.Benchmark.{DynamicFixtures, Fixture}

  @domains_file "priv/domains.exs"

  @doc "All registered static domain keys plus any dynamic-only domains."
  @spec domains() :: [atom()]
  def domains do
    static = Enum.map(load_registry(), & &1.key)
    dynamic_only = DynamicFixtures.domains() -- static
    static ++ dynamic_only
  end

  @doc "Returns the fixtures module for a static domain, or raises."
  @spec module_for(atom()) :: module()
  def module_for(domain) do
    registry = load_registry()

    case Enum.find(registry, &(&1.key == domain)) do
      nil ->
        raise ArgumentError,
              "unknown static domain: #{inspect(domain)}. Known: #{inspect(Enum.map(registry, & &1.key))}"

      entry ->
        entry.fixtures_module
    end
  end

  @doc """
  Returns all fixtures for the given domain — static first, then dynamic.
  Dynamic fixtures whose ID duplicates a static one are silently dropped.
  """
  @spec for_domain(atom()) :: [Fixture.t()]
  def for_domain(domain) do
    static = static_for(domain)
    dynamic = DynamicFixtures.for_domain(domain)

    if static == [] and dynamic == [] do
      raise ArgumentError,
            "unknown benchmark domain: #{inspect(domain)}. Known: #{inspect(domains())}"
    end

    static_ids = MapSet.new(static, & &1.id)
    static ++ Enum.reject(dynamic, &MapSet.member?(static_ids, &1.id))
  end

  @doc "All fixtures across all domains."
  @spec all() :: [Fixture.t()]
  def all, do: Enum.flat_map(domains(), &for_domain/1)

  @doc "Human-readable name for a domain."
  @spec domain_name(atom()) :: String.t()
  def domain_name(domain), do: domain |> module_for() |> apply(:name, [])

  @doc "Valid categories for a domain."
  @spec categories(atom()) :: [atom()]
  def categories(domain), do: domain |> module_for() |> apply(:categories, [])

  defp static_for(domain) do
    case Enum.find(load_registry(), &(&1.key == domain)) do
      nil -> []
      %{fixtures_module: mod} -> apply(mod, :fixtures, [])
    end
  end

  defp load_registry do
    {entries, _} = Code.eval_file(@domains_file)
    entries
  end
end
