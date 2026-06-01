defmodule Reverie.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Reverie.TaskSupervisor},
      Evaluate.Benchmark.DynamicFixtures
    ]

    opts = [strategy: :one_for_one, name: Reverie.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
