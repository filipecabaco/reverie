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
end
