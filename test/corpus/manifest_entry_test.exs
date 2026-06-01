defmodule Corpus.ManifestEntryTest do
  use ExUnit.Case, async: true

  alias Corpus.ManifestEntry

  describe "generate_id/3" do
    test "is deterministic for the same inputs" do
      id1 = ManifestEntry.generate_id(:elixir, :official_hex_docs, "https://hexdocs.pm/ecto")
      id2 = ManifestEntry.generate_id(:elixir, :official_hex_docs, "https://hexdocs.pm/ecto")
      assert id1 == id2
    end

    test "differs when domain changes" do
      id1 = ManifestEntry.generate_id(:elixir, :official_hex_docs, "https://hexdocs.pm/ecto")
      id2 = ManifestEntry.generate_id(:postgres, :official_hex_docs, "https://hexdocs.pm/ecto")
      assert id1 != id2
    end

    test "differs when reference changes" do
      id1 = ManifestEntry.generate_id(:elixir, :official_hex_docs, "https://hexdocs.pm/ecto")
      id2 = ManifestEntry.generate_id(:elixir, :official_hex_docs, "https://hexdocs.pm/phoenix")
      assert id1 != id2
    end

    test "returns a 16-char hex string" do
      id = ManifestEntry.generate_id(:elixir, :changelog, "https://example.com")
      assert String.length(id) == 16
      assert String.match?(id, ~r/^[0-9a-f]+$/)
    end
  end

  describe "to_map/1 and from_map/1" do
    test "round-trips a complete entry" do
      entry = sample_entry()

      round_tripped =
        entry
        |> ManifestEntry.to_map()
        |> Jason.encode!()
        |> Jason.decode!()
        |> ManifestEntry.from_map()

      assert round_tripped.id == entry.id
      assert round_tripped.domain == entry.domain
      assert round_tripped.source_kind == entry.source_kind
      assert round_tripped.reference == entry.reference
      assert round_tripped.training_allowed == entry.training_allowed
      assert round_tripped.redistribution_allowed == entry.redistribution_allowed
      assert round_tripped.terms_review == entry.terms_review
    end

    test "to_map/1 serializes datetime as ISO8601 string" do
      entry = sample_entry()
      map = ManifestEntry.to_map(entry)
      assert is_binary(map["fetched_at"])
      assert String.match?(map["fetched_at"], ~r/^\d{4}-\d{2}-\d{2}T/)
    end

    test "from_map/1 handles nil fetched_at" do
      map = ManifestEntry.to_map(sample_entry()) |> Map.put("fetched_at", nil)
      entry = ManifestEntry.from_map(map)
      assert entry.fetched_at == nil
    end

    test "from_map/1 handles all allowed values" do
      for val <- ["unknown", "true", "false"] do
        map = ManifestEntry.to_map(sample_entry()) |> Map.put("training_allowed", val)
        entry = ManifestEntry.from_map(map)

        expected =
          case val do
            "unknown" -> :unknown
            "true" -> true
            "false" -> false
          end

        assert entry.training_allowed == expected
      end
    end
  end

  defp sample_entry do
    %ManifestEntry{
      id: ManifestEntry.generate_id(:elixir, :official_hex_docs, "https://hexdocs.pm/ecto"),
      domain: :elixir,
      source_kind: :official_hex_docs,
      reference: "https://hexdocs.pm/ecto",
      local_path: "data/elixir/raw/official_hex_docs/ecto.html",
      fetched_at: DateTime.utc_now() |> DateTime.truncate(:second),
      detected_license: "Apache-2.0",
      content_hash: "abc123",
      version_context: "3.11.0",
      terms_review: :pending_review,
      training_allowed: :unknown,
      redistribution_allowed: :unknown,
      contains_personal_data: false
    }
  end
end
