defmodule Research.Brief do
  @enforce_keys [:id, :domain, :topic, :facts, :sources, :created_at]
  defstruct [
    :id,
    :domain,
    :topic,
    :facts,
    :examples,
    :prohibited_patterns,
    :sources,
    :package_versions,
    :created_at,
    :expires_at,
    :status
  ]

  @type source :: %{
          required(:kind) => :official_docs | :official_repo | :release_notes | :community,
          required(:reference) => String.t(),
          required(:retrieved_at) => DateTime.t(),
          optional(:version) => String.t()
        }

  @type status :: :draft | :verified | :usable_for_generation | :stale | :archived

  @type t :: %__MODULE__{
          id: String.t(),
          domain: atom(),
          topic: String.t(),
          facts: [String.t()],
          examples: [map()] | nil,
          prohibited_patterns: [String.t()] | nil,
          sources: [source()],
          package_versions: %{String.t() => String.t()} | nil,
          created_at: DateTime.t(),
          expires_at: DateTime.t() | nil,
          status: status()
        }

  @doc "Returns true if the brief is usable for generating training data or fixtures."
  @spec usable?(t()) :: boolean()
  def usable?(%__MODULE__{status: :usable_for_generation}), do: true
  def usable?(%__MODULE__{}), do: false

  @doc "Returns true if the brief has expired."
  @spec stale?(t()) :: boolean()
  def stale?(%__MODULE__{expires_at: nil}), do: false

  def stale?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
