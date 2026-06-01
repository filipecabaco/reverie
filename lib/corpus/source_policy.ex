defmodule Corpus.SourcePolicy do
  @moduledoc """
  Default rights and review status per source kind (§5.2).

  Source kinds map to policies that set initial values for:
    - `terms_review`          — whether the licence/terms have been checked
    - `training_allowed`      — default assumption for training use
    - `redistribution_allowed` — default assumption for redistribution

  These are starting points. A human (or automated licence scanner) must
  explicitly approve any item before it enters the training or redistribution
  corpus. `:unknown` means "not yet reviewed, do not use".
  """

  alias Corpus.ManifestEntry

  @policies %{
    official_elixir_docs: %{
      terms_review: :pending_review,
      training_allowed: :unknown,
      redistribution_allowed: :unknown,
      notes: "Apache 2.0 — likely approvable; confirm per release"
    },
    official_hex_docs: %{
      terms_review: :pending_review,
      training_allowed: :unknown,
      redistribution_allowed: :unknown,
      notes: "Licence varies per package; must check individually"
    },
    permissive_repo: %{
      terms_review: :pending_review,
      training_allowed: :unknown,
      redistribution_allowed: :unknown,
      notes: "Assumed permissive by source category; confirm licence before use"
    },
    changelog: %{
      terms_review: :pending_review,
      training_allowed: :unknown,
      redistribution_allowed: false,
      notes: "Evidence/retrieval use only by default; not for redistribution"
    },
    github_issue: %{
      terms_review: :unknown,
      training_allowed: false,
      redistribution_allowed: false,
      notes: "Research/discovery only; excluded from training and redistribution by default"
    },
    forum_content: %{
      terms_review: :unknown,
      training_allowed: false,
      redistribution_allowed: false,
      notes: "Discovery only; rights not cleared; excluded from training"
    },
    internal: %{
      terms_review: :approved,
      training_allowed: :unknown,
      redistribution_allowed: false,
      notes: "Internally authored; training use requires explicit approval per item"
    }
  }

  @doc "Apply default policy fields for a source kind to a manifest entry."
  @spec apply_defaults(ManifestEntry.t()) :: ManifestEntry.t()
  def apply_defaults(%ManifestEntry{source_kind: kind} = entry) do
    policy = Map.fetch!(@policies, kind)

    %ManifestEntry{
      entry
      | terms_review: coalesce(entry.terms_review, policy.terms_review),
        training_allowed: coalesce(entry.training_allowed, policy.training_allowed),
        redistribution_allowed:
          coalesce(entry.redistribution_allowed, policy.redistribution_allowed),
        notes: entry.notes || policy.notes
    }
  end

  @doc "Returns true only if a source kind can be fetched at all (not explicitly banned)."
  @spec fetchable?(ManifestEntry.source_kind()) :: boolean()
  def fetchable?(:forum_content), do: false
  def fetchable?(_), do: true

  @doc "Returns the human-readable default policy for a source kind."
  @spec describe(ManifestEntry.source_kind()) :: map()
  def describe(kind), do: Map.fetch!(@policies, kind)

  @doc "All known source kinds."
  @spec source_kinds() :: [ManifestEntry.source_kind()]
  def source_kinds, do: Map.keys(@policies)

  defp coalesce(:unknown, default), do: default
  defp coalesce(existing, _default), do: existing
end
