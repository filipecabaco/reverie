defmodule Domains.Domain do
  @moduledoc """
  Behaviour that every domain configuration module must implement.

  A domain config is the single place that captures what makes a domain
  distinct: its corpus location, source policy, task weights, sandbox
  requirements, and brief lifecycle. The pipeline modules (DatasetBuilder,
  Train.Job, Evaluate.FourWay) are all parameterised by this config — no
  domain-specific code lives in the pipeline.
  """

  @doc "Domain atom key (e.g. :elixir, :postgres)."
  @callback domain() :: atom()

  @doc "Human-readable name."
  @callback name() :: String.t()

  @doc "Full domain configuration map."
  @callback config() :: map()

  @doc "DatasetGen.Config struct for generation pipeline runs."
  @callback generation_config(keyword()) :: DatasetGen.Config.t()

  @doc """
  Corpus source specifications: which packages, repositories, and release
  histories to fetch when building this domain's knowledge base.

  Return a map with any combination of:
    - `:hex_packages` — list of `%{package: String.t(), version: String.t() | nil}`
    - `:repos`        — list of `%{owner: String.t(), repo: String.t(), branch: String.t()}`
    - `:releases`     — list of `%{owner: String.t(), repo: String.t(), max_releases: pos_integer()}`
  """
  @callback sources() :: %{
              optional(:hex_packages) => [%{package: String.t(), optional(:version) => String.t()}],
              optional(:repos) => [
                %{owner: String.t(), repo: String.t(), optional(:branch) => String.t()}
              ],
              optional(:releases) => [
                %{owner: String.t(), repo: String.t(), optional(:max_releases) => pos_integer()}
              ]
            }

  @optional_callbacks [sources: 0]
end
