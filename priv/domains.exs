# Domain registry — edit this file to add or remove domains.
# Run `mix reverie.domain.add --name <name>` to scaffold a new domain.

[
  %{
    key: :elixir,
    name: "Elixir",
    domain_module: Domains.Elixir,
    fixtures_module: Evaluate.Benchmark.Fixtures.Elixir
  },
  %{
    key: :postgres,
    name: "Postgres",
    domain_module: Domains.Postgres,
    fixtures_module: Evaluate.Benchmark.Fixtures.Postgres
  },
  %{
    key: :supabase,
    name: "Supabase",
    domain_module: Domains.Supabase,
    fixtures_module: Evaluate.Benchmark.Fixtures.Supabase
  },
  %{
    key: :typescript,
    name: "TypeScript",
    domain_module: nil,
    fixtures_module: Evaluate.Benchmark.Fixtures.TypeScript
  },
  %{
    key: :testing,
    name: "Testing",
    domain_module: nil,
    fixtures_module: Evaluate.Benchmark.Fixtures.Testing
  },
  %{
    key: :security,
    name: "Security",
    domain_module: nil,
    fixtures_module: Evaluate.Benchmark.Fixtures.Security
  },
  %{
    key: :project_management,
    name: "ProjectManagement",
    domain_module: nil,
    fixtures_module: Evaluate.Benchmark.Fixtures.ProjectManagement
  }
]
