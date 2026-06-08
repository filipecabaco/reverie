defmodule Domains.Elixir do
  @behaviour Domains.Domain

  @impl true
  def domain, do: :elixir

  @impl true
  def name, do: "Elixir"

  @impl true
  def config do
    %{
      domain: :elixir,
      corpus_path: "data/elixir/corpus.db",
      corpus_version: "elixir-corpus-v1",
      source_policy: :official_and_reviewed_repos,
      target_pairs: 5_000,
      requires_retrieval: true,
      task_weights: %{
        implement: 0.30,
        debug: 0.25,
        refactor: 0.15,
        test: 0.20,
        explain: 0.05,
        review: 0.05
      },
      sandbox_profiles: [:stdlib, :ecto, :plug],
      brief_expiry_days: 120,
      split_ratios: %{train: 0.75, validation: 0.10, test: 0.10, regression: 0.05},
      quality: [require_compiled: true, min_answer_bytes: 50]
    }
  end

  @impl true
  def sources do
    %{
      hex_packages: [
        %{package: "elixir"},
        %{package: "mix"},
        %{package: "ex_unit"},
        %{package: "iex"},
        %{package: "ecto"},
        %{package: "ecto_sql"},
        %{package: "phoenix"},
        %{package: "phoenix_live_view"},
        %{package: "plug"},
        %{package: "oban"},
        %{package: "req"},
        %{package: "broadway"},
        %{package: "nimble_parsec"},
        %{package: "telemetry"},
        %{package: "jason"}
      ],
      repos: [
        %{owner: "elixir-lang", repo: "elixir", branch: "main"},
        %{owner: "phoenixframework", repo: "phoenix", branch: "main"},
        %{owner: "elixir-ecto", repo: "ecto", branch: "master"},
        %{owner: "elixir-ecto", repo: "ecto_sql", branch: "master"},
        %{owner: "elixir-plug", repo: "plug", branch: "main"},
        %{owner: "beam-community", repo: "oban", branch: "main"},
        %{owner: "dashbitco", repo: "broadway", branch: "master"},
        %{owner: "wojtekmach", repo: "req", branch: "main"}
      ],
      releases: [
        %{owner: "elixir-lang", repo: "elixir", max_releases: 15},
        %{owner: "phoenixframework", repo: "phoenix", max_releases: 10},
        %{owner: "elixir-ecto", repo: "ecto", max_releases: 10},
        %{owner: "elixir-ecto", repo: "ecto_sql", max_releases: 10}
      ]
    }
  end

  @impl true
  def generation_config(opts \\ []) do
    cfg = config()

    struct(DatasetGen.Config,
      domain: :elixir,
      teacher: Keyword.get(opts, :teacher, DatasetGen.Teacher.Claude),
      target_count: Keyword.get(opts, :target_count, cfg.target_pairs),
      out_path: Keyword.get(opts, :out_path, "data/elixir/generated/candidates.jsonl"),
      task_weights: cfg.task_weights,
      sandbox_slots: Keyword.get(opts, :sandbox_slots, 4),
      generation_concurrency: Keyword.get(opts, :generation_concurrency, 8),
      brief_policy: Keyword.get(opts, :brief_policy, :verified_only),
      max_repairs: Keyword.get(opts, :max_repairs, 1),
      permitted_sandbox_profiles: cfg.sandbox_profiles
    )
  end
end
