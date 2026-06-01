defmodule Domains.Supabase do
  @behaviour Domains.Domain

  @impl true
  def domain, do: :supabase

  @impl true
  def name, do: "Supabase"

  @impl true
  def config do
    %{
      domain: :supabase,
      corpus_path: "data/supabase/corpus.db",
      corpus_version: "supabase-corpus-v1",
      source_policy: :official_and_reviewed_repos,
      target_pairs: 3000,
      requires_retrieval: true,
      task_weights: %{
        # TODO: adjust weights to match this domain's task distribution
        implement: 0.30,
        debug: 0.25,
        refactor: 0.15,
        test: 0.20,
        explain: 0.05,
        review: 0.05
      },
      sandbox_profiles: [],
      brief_expiry_days: 90,
      split_ratios: %{train: 0.75, validation: 0.10, test: 0.10, regression: 0.05},
      quality: [require_compiled: false, min_answer_bytes: 50]
    }
  end

  @impl true
  def generation_config(opts \\ []) do
    cfg = config()

    struct(DatasetGen.Config, [
      domain: :supabase,
      teacher: Keyword.get(opts, :teacher, DatasetGen.Teacher.Claude),
      target_count: Keyword.get(opts, :target_count, cfg.target_pairs),
      out_path: Keyword.get(opts, :out_path, "data/supabase/generated/candidates.jsonl"),
      task_weights: cfg.task_weights,
      sandbox_slots: Keyword.get(opts, :sandbox_slots, 2),
      generation_concurrency: Keyword.get(opts, :generation_concurrency, 8),
      brief_policy: Keyword.get(opts, :brief_policy, :verified_only),
      max_repairs: Keyword.get(opts, :max_repairs, 0),
      permitted_sandbox_profiles: cfg.sandbox_profiles
    ])
  end
end
