defmodule Research.AgentTest do
  use ExUnit.Case, async: true

  alias Research.{Agent, Brief}

  # ---------------------------------------------------------------------------
  # investigate/2
  # ---------------------------------------------------------------------------

  describe "investigate/2 — self-reflective loop" do
    test "returns :ok brief when reviewer is immediately satisfied" do
      reviewer = fn _query, chunks -> {:satisfactory, chunks} end
      retriever = fn _conn, _query, _opts -> [sample_chunk("GenServer processes one message")] end

      assert {:ok, %Brief{}} =
               Agent.investigate("GenServer", reviewer: reviewer, retriever: retriever)
    end

    test "brief contains facts extracted from retrieved chunks" do
      chunk_text = "Task.async_stream runs work concurrently"
      reviewer = fn _q, chunks -> {:satisfactory, chunks} end
      retriever = fn _conn, _q, _opts -> [sample_chunk(chunk_text)] end

      {:ok, brief} = Agent.investigate("Task", reviewer: reviewer, retriever: retriever)
      assert chunk_text in brief.facts
    end

    test "brief has :draft status" do
      reviewer = fn _q, chunks -> {:satisfactory, chunks} end
      retriever = fn _conn, _q, _opts -> [sample_chunk("some fact")] end

      {:ok, brief} = Agent.investigate("topic", reviewer: reviewer, retriever: retriever)
      assert brief.status == :draft
    end

    test "revises query when reviewer requests it" do
      queries_seen = []
      agent = self()

      reviewer = fn query, chunks ->
        send(agent, {:query, query})

        if query == "GenServer" do
          {:revise, "GenServer call cast", "too broad"}
        else
          {:satisfactory, chunks}
        end
      end

      retriever = fn _conn, _q, _opts -> [sample_chunk("fact")] end

      Agent.investigate("GenServer", reviewer: reviewer, retriever: retriever)

      received =
        for _ <- 1..2 do
          receive do
            {:query, q} -> q
          after
            100 -> nil
          end
        end
        |> Enum.reject(&is_nil/1)

      assert "GenServer" in received
      assert "GenServer call cast" in received
      _ = queries_seen
    end

    test "returns coverage_gap error when max_iterations exhausted" do
      reviewer = fn _q, _chunks -> {:revise, "new query", "never satisfied"} end
      retriever = fn _conn, _q, _opts -> [sample_chunk("fact")] end

      assert {:error, {:coverage_gap, "topic"}} =
               Agent.investigate("topic",
                 reviewer: reviewer,
                 retriever: retriever,
                 max_iterations: 2
               )
    end

    test "returns coverage_gap when no chunks ever retrieved" do
      reviewer = fn _q, [] -> {:revise, "broader", "no results"} end
      retriever = fn _conn, _q, _opts -> [] end

      assert {:error, {:coverage_gap, _}} =
               Agent.investigate("obscure topic",
                 reviewer: reviewer,
                 retriever: retriever,
                 max_iterations: 2
               )
    end

    test "brief sources include chunk source_references" do
      chunk = %{
        text: "fact",
        source_reference: "hexdocs/genserver",
        domain: :elixir,
        metadata: %{}
      }

      reviewer = fn _q, chunks -> {:satisfactory, chunks} end
      retriever = fn _conn, _q, _opts -> [chunk] end

      {:ok, brief} = Agent.investigate("GenServer", reviewer: reviewer, retriever: retriever)
      refs = Enum.map(brief.sources, & &1.reference)
      assert "hexdocs/genserver" in refs
    end
  end

  # ---------------------------------------------------------------------------
  # verify_candidate/2
  # ---------------------------------------------------------------------------

  describe "verify_candidate/2" do
    test "returns :ok when answer contains evidence from brief facts" do
      brief = brief_with_facts(["GenServer processes one message at a time"])
      candidate = candidate_with_answer("GenServer processes one message at a time in Elixir")
      assert :ok = Agent.verify_candidate(candidate, brief)
    end

    test "returns :missing_evidence when answer shares no keywords with facts" do
      brief = brief_with_facts(["GenServer serializes message processing"])
      candidate = candidate_with_answer("def add(a, b), do: a + b")
      assert {:error, :missing_evidence} = Agent.verify_candidate(candidate, brief)
    end

    test "returns :prohibited_pattern when answer matches a prohibited pattern" do
      brief = %Brief{
        brief_with_facts(["GenServer timeouts"])
        | prohibited_patterns: ["use :infinity timeout"]
      }

      candidate =
        candidate_with_answer("GenServer.call(pid, msg, :infinity) # use :infinity timeout here")

      assert {:error, :prohibited_pattern} = Agent.verify_candidate(candidate, brief)
    end

    test "prohibited pattern check is case-insensitive" do
      brief = %Brief{brief_with_facts(["some fact"]) | prohibited_patterns: ["Eval.string"]}
      candidate = candidate_with_answer("avoid eval.string in production")
      assert {:error, :prohibited_pattern} = Agent.verify_candidate(candidate, brief)
    end

    test "returns :missing_brief when brief is nil" do
      assert {:error, :missing_brief} = Agent.verify_candidate(candidate_with_answer("code"), nil)
    end

    test "passes when brief has no prohibited patterns" do
      brief = %Brief{brief_with_facts(["Task concurrency"]) | prohibited_patterns: nil}
      candidate = candidate_with_answer("use Task for concurrency")
      assert :ok = Agent.verify_candidate(candidate, brief)
    end
  end

  # ---------------------------------------------------------------------------
  # Brief lifecycle transitions
  # ---------------------------------------------------------------------------

  describe "lifecycle transitions" do
    test "mark_verified/1 transitions draft → verified" do
      brief = %Brief{sample_brief() | status: :draft}
      assert %Brief{status: :verified} = Agent.mark_verified(brief)
    end

    test "mark_verified/1 is a no-op for non-draft briefs" do
      brief = %Brief{sample_brief() | status: :verified}
      assert %Brief{status: :verified} = Agent.mark_verified(brief)
    end

    test "mark_usable/1 transitions verified → usable_for_generation" do
      brief = %Brief{sample_brief() | status: :verified}
      assert %Brief{status: :usable_for_generation} = Agent.mark_usable(brief)
    end

    test "mark_usable/1 is a no-op for non-verified briefs" do
      brief = %Brief{sample_brief() | status: :draft}
      assert %Brief{status: :draft} = Agent.mark_usable(brief)
    end

    test "mark_stale/1 marks any brief stale" do
      for status <- [:draft, :verified, :usable_for_generation] do
        brief = %Brief{sample_brief() | status: status}
        assert %Brief{status: :stale} = Agent.mark_stale(brief)
      end
    end

    test "archive/1 archives any brief" do
      brief = sample_brief()
      assert %Brief{status: :archived} = Agent.archive(brief)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp sample_chunk(text, source_ref \\ "hexdocs/elixir") do
    %{text: text, source_reference: source_ref, domain: :elixir, metadata: %{}}
  end

  defp sample_brief do
    %Brief{
      id: "brief-test-001",
      domain: :elixir,
      topic: "GenServer",
      status: :draft,
      facts: ["GenServer processes one message at a time"],
      examples: nil,
      prohibited_patterns: nil,
      sources: [],
      package_versions: %{},
      created_at: DateTime.utc_now(),
      expires_at: nil
    }
  end

  defp brief_with_facts(facts) do
    %Brief{sample_brief() | facts: facts}
  end

  defp candidate_with_answer(text) do
    %{
      messages: [
        %{role: "user", content: "Question"},
        %{role: "assistant", content: text}
      ]
    }
  end
end
