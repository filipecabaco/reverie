defmodule DatasetGen.TaskSpec do
  @moduledoc """
  Describes one generation request: what to ask the teacher to produce.

  `task_type` maps to the teacher's prompt template.
  `difficulty` is advisory — the teacher uses it to calibrate complexity.
  `brief_id` links the generated candidate back to its evidence source.
  """

  @enforce_keys [:domain, :task_type]
  defstruct [
    :domain,
    :task_type,
    :topic,
    :brief_id,
    difficulty: :medium
  ]

  @type task_type :: :implement | :debug | :refactor | :test | :explain | :review
  @type difficulty :: :easy | :medium | :hard

  @type t :: %__MODULE__{
          domain: atom(),
          task_type: task_type(),
          # When nil the teacher chooses an appropriate topic for the domain.
          topic: String.t() | nil,
          brief_id: String.t() | nil,
          difficulty: difficulty()
        }
end
