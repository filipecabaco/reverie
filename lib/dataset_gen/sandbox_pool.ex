defmodule DatasetGen.SandboxPool do
  @moduledoc """
  Semaphore that bounds concurrent sandbox container invocations.

  The sandbox capacity limit must be independent of Broadway processor
  concurrency — a busy API rate allows many processors, but too many
  simultaneous containers exhaust memory and CPU (§8.5).

  Callers that cannot immediately acquire a slot are queued and replied
  to in FIFO order as slots are released. The pool never exceeds
  `slots` concurrent holders.
  """

  use GenServer

  @default_timeout 60_000

  def start_link(opts) do
    slots = Keyword.fetch!(opts, :slots)
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, slots, name: name)
  end

  @doc "Acquire one slot. Blocks until a slot is available or timeout fires."
  @spec acquire(GenServer.server(), timeout()) :: :ok
  def acquire(pool, timeout \\ @default_timeout) do
    GenServer.call(pool, :acquire, timeout)
  end

  @doc "Release a previously acquired slot."
  @spec release(GenServer.server()) :: :ok
  def release(pool) do
    GenServer.cast(pool, :release)
  end

  @doc "Return {available, waiting} for observability."
  @spec stats(GenServer.server()) :: {non_neg_integer(), non_neg_integer()}
  def stats(pool) do
    GenServer.call(pool, :stats)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(slots) when is_integer(slots) and slots > 0 do
    {:ok, %{available: slots, max: slots, waiting: :queue.new()}}
  end

  @impl true
  def handle_call(:acquire, _from, %{available: n} = state) when n > 0 do
    {:reply, :ok, %{state | available: n - 1}}
  end

  def handle_call(:acquire, from, %{available: 0} = state) do
    {:noreply, %{state | waiting: :queue.in(from, state.waiting)}}
  end

  def handle_call(:stats, _from, state) do
    {:reply, {state.available, :queue.len(state.waiting)}, state}
  end

  @impl true
  def handle_cast(:release, state) do
    case :queue.out(state.waiting) do
      {{:value, from}, rest} ->
        GenServer.reply(from, :ok)
        {:noreply, %{state | waiting: rest}}

      {:empty, _} ->
        {:noreply, %{state | available: min(state.available + 1, state.max)}}
    end
  end
end
