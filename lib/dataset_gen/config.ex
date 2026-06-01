defmodule DatasetGen.Config do
  @moduledoc """
  Generation pipeline configuration (§8.1).

  `teacher` must implement `DatasetGen.Teacher`.
  `brief_policy` controls whether the generator fetches evidence briefs:
    :none           — skip brief lookup entirely
    :verified_only  — only attach briefs with status :usable_for_generation
    :any            — attach any available brief including drafts
  """

  @enforce_keys [:domain, :teacher, :target_count, :out_path]
  defstruct [
    :domain,
    :teacher,
    :target_count,
    :out_path,
    :checkpoint_path,
    :judge,
    generation_concurrency: 8,
    sandbox_slots: 4,
    judge_threshold: 4.0,
    max_repairs: 1,
    task_weights: %{
      implement: 0.30,
      debug: 0.25,
      refactor: 0.15,
      test: 0.20,
      explain: 0.05,
      review: 0.05
    },
    permitted_sandbox_profiles: [:stdlib],
    brief_policy: :verified_only
  ]

  @type brief_policy :: :none | :verified_only | :any

  @type t :: %__MODULE__{
          domain: atom(),
          teacher: module(),
          target_count: pos_integer(),
          out_path: Path.t(),
          checkpoint_path: Path.t() | nil,
          judge: module() | nil,
          generation_concurrency: pos_integer(),
          sandbox_slots: pos_integer(),
          judge_threshold: float(),
          max_repairs: non_neg_integer(),
          task_weights: %{atom() => float()},
          permitted_sandbox_profiles: [atom()],
          brief_policy: brief_policy()
        }
end
