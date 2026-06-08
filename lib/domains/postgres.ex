defmodule Domains.Postgres do
  @behaviour Domains.Domain

  @impl true
  def domain, do: :postgres

  @impl true
  def name, do: "Postgres"

  @impl true
  def config do
    %{
      domain: :postgres,
      corpus_path: "data/postgres/corpus.db",
      corpus_version: "postgres-corpus-v1",
      source_policy: :official_and_reviewed_repos,
      target_pairs: 3_000,
      requires_retrieval: true,
      task_weights: %{
        schema_design: 0.25,
        querying: 0.30,
        indexing: 0.15,
        transactions: 0.15,
        performance: 0.10,
        debugging: 0.05
      },
      # Postgres queries can't sandbox-compile (need a live DB).
      # PL/pgSQL and migration syntax aren't valid Elixir, so sandbox_profiles is empty.
      # All quality checks rely on rubric/judge rather than compile gate.
      sandbox_profiles: [],
      brief_expiry_days: 90,
      split_ratios: %{train: 0.75, validation: 0.10, test: 0.10, regression: 0.05},
      quality: [require_compiled: false, min_answer_bytes: 80]
    }
  end

  @impl true
  def sources do
    %{
      hex_packages: [
        %{package: "postgrex"},
        %{package: "ecto"},
        %{package: "ecto_sql"},
        %{package: "ecto_psql_extras"}
      ],
      repos: [
        %{owner: "elixir-ecto", repo: "ecto_sql", branch: "master"},
        %{owner: "elixir-ecto", repo: "postgrex", branch: "master"},
        %{owner: "elixir-ecto", repo: "ecto", branch: "master"},
        %{owner: "pawurb", repo: "ecto_psql_extras", branch: "main"}
      ],
      releases: [
        %{owner: "elixir-ecto", repo: "ecto_sql", max_releases: 10},
        %{owner: "elixir-ecto", repo: "postgrex", max_releases: 10}
      ]
    }
  end

  @impl true
  def generation_config(opts \\ []) do
    cfg = config()

    struct(DatasetGen.Config,
      domain: :postgres,
      teacher: Keyword.get(opts, :teacher, DatasetGen.Teacher.Claude),
      target_count: Keyword.get(opts, :target_count, cfg.target_pairs),
      out_path: Keyword.get(opts, :out_path, "data/postgres/generated/candidates.jsonl"),
      task_weights: cfg.task_weights,
      sandbox_slots: Keyword.get(opts, :sandbox_slots, 2),
      generation_concurrency: Keyword.get(opts, :generation_concurrency, 8),
      brief_policy: Keyword.get(opts, :brief_policy, :verified_only),
      max_repairs: Keyword.get(opts, :max_repairs, 0),
      permitted_sandbox_profiles: cfg.sandbox_profiles
    )
  end
end
