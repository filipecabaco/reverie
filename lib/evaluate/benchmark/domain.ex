defmodule Evaluate.Benchmark.Domain do
  @moduledoc """
  Behaviour that every domain fixture module must implement.

  Each domain is self-contained: its own categories, difficulty spread,
  sandbox requirements, and fixture list. The `Evaluate.Benchmark` API
  stays generic and delegates to the domain module via this behaviour.
  """

  alias Evaluate.Benchmark.Fixture

  @doc "Human-readable name for the domain."
  @callback name() :: String.t()

  @doc "Atom categories valid for this domain (used for reporting and filtering)."
  @callback categories() :: [atom()]

  @doc "All fixtures for this domain."
  @callback fixtures() :: [Fixture.t()]
end
