defmodule Domains.RegistryTest do
  use ExUnit.Case, async: true

  alias Domains.Registry

  describe "Registry.domains/0" do
    test "includes both elixir and postgres" do
      domains = Registry.domains()
      assert :elixir in domains
      assert :postgres in domains
    end
  end

  describe "Registry.module_for/1" do
    test "returns the correct module for each domain" do
      assert Registry.module_for(:elixir) == Domains.Elixir
      assert Registry.module_for(:postgres) == Domains.Postgres
    end

    test "raises for unknown domain" do
      assert_raise ArgumentError, fn -> Registry.module_for(:unknown) end
    end
  end

  describe "Registry.config/1" do
    test "each domain config has the required keys" do
      required = [:domain, :corpus_path, :target_pairs, :task_weights, :split_ratios, :quality]

      for domain <- Registry.domains() do
        cfg = Registry.config(domain)

        for key <- required do
          assert Map.has_key?(cfg, key), "#{domain}: config missing :#{key}"
        end
      end
    end

    test "domain keys match the config :domain field" do
      for domain <- Registry.domains() do
        cfg = Registry.config(domain)
        assert cfg.domain == domain, "#{domain}: config.domain mismatch"
      end
    end

    test "task_weights sum to approximately 1.0" do
      for domain <- Registry.domains() do
        cfg = Registry.config(domain)
        total = cfg.task_weights |> Map.values() |> Enum.sum()
        assert_in_delta total, 1.0, 0.01, "#{domain}: task_weights don't sum to 1.0"
      end
    end

    test "split_ratios sum to approximately 1.0" do
      for domain <- Registry.domains() do
        cfg = Registry.config(domain)
        total = cfg.split_ratios |> Map.values() |> Enum.sum()
        assert_in_delta total, 1.0, 0.01, "#{domain}: split_ratios don't sum to 1.0"
      end
    end
  end

  describe "Registry.generation_config/2" do
    test "returns a DatasetGen.Config struct for each domain" do
      for domain <- Registry.domains() do
        cfg = Registry.generation_config(domain)
        assert %DatasetGen.Config{} = cfg, "#{domain}: expected DatasetGen.Config"
        assert cfg.domain == domain
      end
    end

    test "opts override defaults" do
      cfg = Registry.generation_config(:elixir, target_count: 999, max_repairs: 2)
      assert cfg.target_count == 999
      assert cfg.max_repairs == 2
    end

    test "postgres domain has require_compiled: false in quality opts" do
      cfg = Registry.config(:postgres)
      assert Keyword.get(cfg.quality, :require_compiled) == false
    end

    test "elixir domain has require_compiled: true in quality opts" do
      cfg = Registry.config(:elixir)
      assert Keyword.get(cfg.quality, :require_compiled) == true
    end
  end

  describe "Registry.name/1" do
    test "returns human-readable names" do
      assert Registry.name(:elixir) == "Elixir"
      assert Registry.name(:postgres) == "Postgres"
    end
  end
end
