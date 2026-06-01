defmodule Reverie.MixProject do
  use Mix.Project

  def project do
    [
      app: :reverie,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Reverie.Application, []}
    ]
  end

  defp aliases do
    [
      "sandbox.build": ["cmd docker build -t dataset-gen-sandbox:stdlib priv/sandbox/"]
    ]
  end

  defp deps do
    [
      # HTTP
      {:req, "~> 0.5"},

      # Concurrency / job processing
      {:broadway, "~> 1.1"},
      {:oban, "~> 2.18"},

      # Data
      {:explorer, "~> 0.10"},

      # SQLite (retrieval corpus)
      {:exqlite, "~> 0.23"},
      {:ecto_sqlite3, "~> 0.18"},
      {:ecto, "~> 3.12"},

      # S3-compatible artifact storage
      {:ex_aws, "~> 2.5"},
      {:ex_aws_s3, "~> 2.5"},
      {:hackney, "~> 1.20"},
      {:sweet_xml, "~> 0.7"},

      # Remote burst / GPU runners
      {:flame, "~> 0.5"},

      # Python training bridge
      {:pythonx, "~> 0.4"},

      # Observability
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.1"},

      # Dev / test
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
