defmodule Evaluate.Benchmark.Fixture do
  @enforce_keys [:id, :category, :difficulty, :prompt, :tags, :scoreable]
  defstruct [
    :id,
    :category,
    :difficulty,
    :prompt,
    :test_code,
    :tags,
    :scoreable,
    :sandbox_profile
  ]

  @type category ::
          :pattern_matching
          | :genserver
          | :supervision
          | :ecto
          | :exunit
          | :otp
          | :debugging
          | :regression

  @type difficulty :: :easy | :medium | :hard

  @type t :: %__MODULE__{
          id: String.t(),
          category: category(),
          difficulty: difficulty(),
          prompt: String.t(),
          test_code: String.t() | nil,
          tags: [atom()],
          scoreable: boolean(),
          sandbox_profile: atom()
        }
end
