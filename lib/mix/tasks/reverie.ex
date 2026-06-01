defmodule Mix.Tasks.Reverie do
  use Mix.Task

  @shortdoc "List all Reverie tasks"

  @moduledoc """
  Reverie domain adapter training platform.

  Available tasks:

      mix reverie.investigate   Research a topic and store a brief
      mix reverie.generate      Generate training candidates for a domain
      mix reverie.freeze        Freeze a dataset snapshot from generated candidates
      mix reverie.benchmark     Run the benchmark against a model endpoint
      mix reverie.status        Show pipeline status for a domain
  """

  def run(_) do
    Mix.shell().info(@moduledoc)
  end
end
