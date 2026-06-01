defmodule Domains.Registry do
  @moduledoc """
  Loads the domain registry from `priv/domains.exs` at runtime.

  To add or remove a domain, edit `priv/domains.exs` — no Elixir source
  changes required. `mix reverie.domain.add` does this automatically.
  """

  @domains_file "priv/domains.exs"

  @doc "Domain keys that have a full domain_module (config + generation_config)."
  @spec domains() :: [atom()]
  def domains do
    load()
    |> Enum.filter(&(&1.domain_module != nil))
    |> Enum.map(& &1.key)
  end

  @doc "The entry map for a domain key."
  @spec entry(atom()) :: map()
  def entry(domain) do
    Enum.find(load(), &(&1.key == domain)) ||
      raise ArgumentError,
            "unknown domain: #{inspect(domain)}. Known: #{inspect(domains())}"
  end

  @doc "The module implementing `Domains.Domain` for a given key."
  @spec module_for(atom()) :: module()
  def module_for(domain), do: entry(domain).domain_module

  @doc "Domain config map."
  @spec config(atom()) :: map()
  def config(domain), do: domain |> module_for() |> apply(:config, [])

  @doc "DatasetGen.Config struct, with optional overrides."
  @spec generation_config(atom(), keyword()) :: DatasetGen.Config.t()
  def generation_config(domain, opts \\ []) do
    domain |> module_for() |> apply(:generation_config, [opts])
  end

  @doc "Human-readable domain name."
  @spec name(atom()) :: String.t()
  def name(domain), do: entry(domain).name

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp load do
    {entries, _} = Code.eval_file(@domains_file)
    entries
  end
end
