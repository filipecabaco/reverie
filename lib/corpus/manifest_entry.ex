defmodule Corpus.ManifestEntry do
  @moduledoc """
  One fetched item in the raw corpus. Every item must have a manifest entry
  before it can be used for briefs or training data.

  The `training_allowed` and `redistribution_allowed` fields gate downstream use:
    :unknown  — not yet reviewed (default for most source kinds)
    true      — explicitly approved
    false     — explicitly excluded
  """

  @enforce_keys [:id, :domain, :source_kind, :reference, :fetched_at]
  defstruct [
    :id,
    :domain,
    :source_kind,
    :reference,
    :local_path,
    :fetched_at,
    :detected_license,
    :content_hash,
    :version_context,
    :notes,
    terms_review: :unknown,
    training_allowed: :unknown,
    redistribution_allowed: :unknown,
    contains_personal_data: :unknown
  ]

  @type source_kind ::
          :official_elixir_docs
          | :official_hex_docs
          | :permissive_repo
          | :changelog
          | :github_issue
          | :forum_content
          | :internal

  @type review_status :: :unknown | :approved | :rejected | :pending_review
  @type allowed :: :unknown | boolean()

  @type t :: %__MODULE__{
          id: String.t(),
          domain: atom(),
          source_kind: source_kind(),
          reference: String.t(),
          local_path: Path.t() | nil,
          fetched_at: DateTime.t(),
          detected_license: String.t() | nil,
          content_hash: String.t() | nil,
          version_context: String.t() | nil,
          notes: String.t() | nil,
          terms_review: review_status(),
          training_allowed: allowed(),
          redistribution_allowed: allowed(),
          contains_personal_data: allowed()
        }

  @doc "Generate a deterministic ID from domain + source_kind + reference."
  @spec generate_id(atom(), source_kind(), String.t()) :: String.t()
  def generate_id(domain, source_kind, reference) do
    :crypto.hash(:sha256, "#{domain}:#{source_kind}:#{reference}")
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  @doc "Serialize to a string-keyed map for JSONL storage."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = entry) do
    %{
      "id" => entry.id,
      "domain" => Atom.to_string(entry.domain),
      "source_kind" => Atom.to_string(entry.source_kind),
      "reference" => entry.reference,
      "local_path" => entry.local_path,
      "fetched_at" => entry.fetched_at && DateTime.to_iso8601(entry.fetched_at),
      "detected_license" => entry.detected_license,
      "content_hash" => entry.content_hash,
      "version_context" => entry.version_context,
      "notes" => entry.notes,
      "terms_review" => Atom.to_string(entry.terms_review),
      "training_allowed" => serialize_allowed(entry.training_allowed),
      "redistribution_allowed" => serialize_allowed(entry.redistribution_allowed),
      "contains_personal_data" => serialize_allowed(entry.contains_personal_data)
    }
  end

  @doc "Deserialize from a plain map (as loaded from JSONL)."
  @spec from_map(map()) :: t()
  def from_map(map) do
    %__MODULE__{
      id: map["id"],
      domain: String.to_existing_atom(map["domain"]),
      source_kind: String.to_existing_atom(map["source_kind"]),
      reference: map["reference"],
      local_path: map["local_path"],
      fetched_at: map["fetched_at"] && parse_datetime(map["fetched_at"]),
      detected_license: map["detected_license"],
      content_hash: map["content_hash"],
      version_context: map["version_context"],
      notes: map["notes"],
      terms_review: to_status(map["terms_review"]),
      training_allowed: to_allowed(map["training_allowed"]),
      redistribution_allowed: to_allowed(map["redistribution_allowed"]),
      contains_personal_data: to_allowed(map["contains_personal_data"])
    }
  end

  defp serialize_allowed(:unknown), do: "unknown"
  defp serialize_allowed(true), do: "true"
  defp serialize_allowed(false), do: "false"

  defp parse_datetime(nil), do: nil
  defp parse_datetime(str), do: elem(DateTime.from_iso8601(str), 1)

  defp to_status(nil), do: :unknown
  defp to_status(s) when is_binary(s), do: String.to_existing_atom(s)
  defp to_status(s) when is_atom(s), do: s

  defp to_allowed(nil), do: :unknown
  defp to_allowed("unknown"), do: :unknown
  defp to_allowed(true), do: true
  defp to_allowed(false), do: false
  defp to_allowed("true"), do: true
  defp to_allowed("false"), do: false
end
