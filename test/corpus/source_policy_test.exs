defmodule Corpus.SourcePolicyTest do
  use ExUnit.Case, async: true

  alias Corpus.{ManifestEntry, SourcePolicy}

  describe "apply_defaults/1" do
    test "official_hex_docs sets pending_review and :unknown training" do
      entry = bare_entry(:official_hex_docs)
      result = SourcePolicy.apply_defaults(entry)
      assert result.terms_review == :pending_review
      assert result.training_allowed == :unknown
      assert result.redistribution_allowed == :unknown
    end

    test "github_issue sets training_allowed: false" do
      result = bare_entry(:github_issue) |> SourcePolicy.apply_defaults()
      assert result.training_allowed == false
      assert result.redistribution_allowed == false
    end

    test "forum_content sets training_allowed: false" do
      result = bare_entry(:forum_content) |> SourcePolicy.apply_defaults()
      assert result.training_allowed == false
      assert result.redistribution_allowed == false
    end

    test "internal sets terms_review: :approved" do
      result = bare_entry(:internal) |> SourcePolicy.apply_defaults()
      assert result.terms_review == :approved
    end

    test "does not overwrite an already-set training_allowed" do
      entry = %{bare_entry(:official_hex_docs) | training_allowed: true}
      result = SourcePolicy.apply_defaults(entry)
      assert result.training_allowed == true
    end

    test "does not overwrite terms_review when already set" do
      entry = %{bare_entry(:official_hex_docs) | terms_review: :rejected}
      result = SourcePolicy.apply_defaults(entry)
      assert result.terms_review == :rejected
    end

    test "applies notes from policy when entry has none" do
      result = bare_entry(:changelog) |> SourcePolicy.apply_defaults()
      assert is_binary(result.notes)
      assert String.length(result.notes) > 0
    end
  end

  describe "fetchable?/1" do
    test "forum_content is not fetchable" do
      refute SourcePolicy.fetchable?(:forum_content)
    end

    test "all other source kinds are fetchable" do
      for kind <- SourcePolicy.source_kinds(), kind != :forum_content do
        assert SourcePolicy.fetchable?(kind), "expected #{kind} to be fetchable"
      end
    end
  end

  describe "source_kinds/0" do
    test "includes all expected kinds" do
      kinds = SourcePolicy.source_kinds()

      expected =
        ~w(official_elixir_docs official_hex_docs permissive_repo changelog github_issue forum_content internal)a

      for k <- expected, do: assert(k in kinds, "missing: #{k}")
    end
  end

  describe "describe/1" do
    test "returns a map with required policy fields" do
      for kind <- SourcePolicy.source_kinds() do
        policy = SourcePolicy.describe(kind)
        assert Map.has_key?(policy, :terms_review), "#{kind}: missing :terms_review"
        assert Map.has_key?(policy, :training_allowed), "#{kind}: missing :training_allowed"

        assert Map.has_key?(policy, :redistribution_allowed),
               "#{kind}: missing :redistribution_allowed"
      end
    end
  end

  defp bare_entry(source_kind) do
    %ManifestEntry{
      id: "test-id",
      domain: :elixir,
      source_kind: source_kind,
      reference: "https://example.com",
      fetched_at: DateTime.utc_now()
    }
  end
end
