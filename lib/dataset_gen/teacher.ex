defmodule DatasetGen.Teacher do
  @moduledoc """
  Behaviour for dataset generation teachers.

  A teacher receives a task spec and an optional evidence brief,
  and must return a candidate map with the keys:
    :instruction  — the user-facing prompt
    :answer       — the model's response
    :code         — Elixir source code (or nil)
    :test_code    — ExUnit test code (or nil)

  Teachers must also implement `repair/3` to fix a candidate that
  failed validation, given the validation error message.
  """

  alias DatasetGen.TaskSpec
  alias Research.Brief

  @callback generate(spec :: TaskSpec.t(), brief :: Brief.t() | nil, opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @callback repair(candidate :: map(), validation_error :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
end
