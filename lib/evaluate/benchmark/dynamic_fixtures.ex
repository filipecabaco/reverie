defmodule Evaluate.Benchmark.DynamicFixtures do
  @moduledoc """
  Runtime store for benchmark fixtures generated from research briefs.

  Fixtures are held in ETS (fast reads, no persistence across restarts).
  This is intentional — generated fixtures are derived from the corpus and
  can be regenerated. For long-lived fixtures, promote them to the appropriate
  static domain module.

  Duplicate IDs within a domain are silently dropped (first write wins),
  so regenerating from the same brief is idempotent.
  """

  use GenServer

  alias Evaluate.Benchmark.Fixture

  @table :dynamic_fixtures

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, :ok, [{:name, __MODULE__} | opts])

  @doc "Add fixtures for a domain. Duplicate IDs are ignored."
  @spec add(atom(), [Fixture.t()]) :: :ok
  def add(domain, fixtures) when is_atom(domain) and is_list(fixtures) do
    GenServer.call(__MODULE__, {:add, domain, fixtures})
  end

  @doc "All dynamic fixtures for a domain."
  @spec for_domain(atom()) :: [Fixture.t()]
  def for_domain(domain) when is_atom(domain) do
    case :ets.lookup(@table, domain) do
      [{^domain, fixtures}] -> fixtures
      [] -> []
    end
  end

  @doc "All domains that have dynamic fixtures registered."
  @spec domains() :: [atom()]
  def domains do
    :ets.tab2list(@table) |> Enum.map(fn {domain, _} -> domain end)
  end

  @doc "Remove all dynamic fixtures for a domain."
  @spec clear(atom()) :: :ok
  def clear(domain) when is_atom(domain) do
    GenServer.call(__MODULE__, {:clear, domain})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    {:ok, :no_state}
  end

  @impl true
  def handle_call({:add, domain, new_fixtures}, _from, state) do
    existing = for_domain(domain)
    existing_ids = MapSet.new(existing, & &1.id)

    merged =
      existing ++
        Enum.reject(new_fixtures, fn f -> MapSet.member?(existing_ids, f.id) end)

    :ets.insert(@table, {domain, merged})
    {:reply, :ok, state}
  end

  def handle_call({:clear, domain}, _from, state) do
    :ets.delete(@table, domain)
    {:reply, :ok, state}
  end
end
