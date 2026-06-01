defmodule Train.Bakeoff.Compatibility do
  @moduledoc """
  Compatibility checklist for a model candidate (§12.2).

  Each gate is verified once manually (or via a smoke-train) before a
  candidate is committed to. Results are recorded as a map keyed by gate name
  and stored alongside the bake-off report for audit.

  Gates:
    :base_loads          — model loads without error at 4-bit
    :adapter_unmerged    — adapter can be loaded without merging into base weights
    :adapter_switch      — per-request adapter switching works correctly
    :quant_memory_ok     — quantized base fits within the GPU memory budget
    :trained_adapter_loads — the adapter produced by Train.Job reloads cleanly
    :tokenizer_parity    — prompts tokenize identically between Python + Elixir
    :retrieval_budget    — retrieval context + system prompt fit within max_seq_length
    :observability       — latency, adapter id, and failure are measurable
  """

  @gates ~w(
    base_loads
    adapter_unmerged
    adapter_switch
    quant_memory_ok
    trained_adapter_loads
    tokenizer_parity
    retrieval_budget
    observability
  )a

  @type gate :: atom()
  @type status :: :pass | :fail | :skip | :pending
  @type result :: %{gate: gate(), status: status(), note: String.t() | nil}
  @type t :: %{gate() => result()}

  @doc "Returns a blank checklist (all gates :pending) for a candidate."
  @spec new() :: t()
  def new do
    Map.new(@gates, fn gate ->
      {gate, %{gate: gate, status: :pending, note: nil}}
    end)
  end

  @doc "Mark a gate with a status and optional note."
  @spec mark(t(), gate(), status(), String.t() | nil) :: t()
  def mark(checklist, gate, status, note \\ nil)
      when gate in @gates and status in [:pass, :fail, :skip] do
    Map.update!(checklist, gate, fn entry -> %{entry | status: status, note: note} end)
  end

  @doc "Returns true only when every non-skipped gate has passed."
  @spec passed?(t()) :: boolean()
  def passed?(checklist) do
    checklist
    |> Map.values()
    |> Enum.reject(&(&1.status == :skip))
    |> Enum.all?(&(&1.status == :pass))
  end

  @doc "Returns the list of gate names that failed."
  @spec failures(t()) :: [gate()]
  def failures(checklist) do
    checklist
    |> Map.values()
    |> Enum.filter(&(&1.status == :fail))
    |> Enum.map(& &1.gate)
  end

  @doc "Returns the list of gate names still pending."
  @spec pending(t()) :: [gate()]
  def pending(checklist) do
    checklist
    |> Map.values()
    |> Enum.filter(&(&1.status == :pending))
    |> Enum.map(& &1.gate)
  end

  @doc "All gate names, in order."
  @spec gates() :: [gate()]
  def gates, do: @gates

  @doc "Render a summary string."
  @spec summary(t(), Train.ModelCandidate.t()) :: String.t()
  def summary(checklist, candidate) do
    rows =
      @gates
      |> Enum.map_join("\n", fn gate ->
        %{status: status, note: note} = checklist[gate]
        icon = icon(status)
        note_text = if note, do: " — #{note}", else: ""
        "  #{icon} #{gate}#{note_text}"
      end)

    overall = if passed?(checklist), do: "PASS", else: "FAIL / INCOMPLETE"

    """
    Compatibility: #{candidate.name} (#{candidate.id})
    #{rows}

    Overall: #{overall}
    """
  end

  defp icon(:pass), do: "✓"
  defp icon(:fail), do: "✗"
  defp icon(:skip), do: "–"
  defp icon(:pending), do: "?"
end
