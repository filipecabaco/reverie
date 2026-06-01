defmodule Research.Agent do
  @moduledoc """
  Investigation workflow using the self-reflective RAG loop (§3.3).

  The loop: retrieve top-k → review (relevant? sufficient? current?) →
  satisfactory? yes → build brief / no → revise query → retrieve again.
  Capped at `max_iterations` to bound cost.

  Both the retriever and reviewer are injectable so the loop runs without
  a live LLM or corpus in tests.
  """

  alias Corpus.Store
  alias Research.Brief

  @max_iterations 3

  @type retriever :: (conn :: term(), query :: String.t(), opts :: keyword() -> [map()])
  @type review_result :: {:satisfactory, [map()]} | {:revise, String.t(), String.t()}
  @type reviewer :: (query :: String.t(), chunks :: [map()] -> review_result())

  # ---------------------------------------------------------------------------
  # Investigation
  # ---------------------------------------------------------------------------

  @doc """
  Investigate a topic using the self-reflective RAG loop.

  Options:
    - `:conn`           — open Corpus.Store connection (required unless `:retriever` overridden)
    - `:domain`         — atom domain for filtering retrieval results
    - `:retriever`      — injectable retriever function; receives (conn, query, opts)
    - `:reviewer`       — injectable reviewer function; receives (query, chunks)
    - `:max_iterations` — loop cap (default #{@max_iterations})
    - `:sources`        — explicit sources to attach to the brief

  Returns `{:ok, Brief.t()}` or `{:error, reason}`.
  """
  @spec investigate(String.t(), keyword()) :: {:ok, Brief.t()} | {:error, term()}
  def investigate(topic, opts \\ []) do
    conn = opts[:conn]
    domain = Keyword.get(opts, :domain, :elixir)
    max_iter = Keyword.get(opts, :max_iterations, @max_iterations)
    sources = Keyword.get(opts, :sources, [])
    retriever = Keyword.get(opts, :retriever, &default_retriever/3)
    reviewer = Keyword.get(opts, :reviewer, &default_reviewer/2)

    case loop(topic, topic, conn, domain, retriever, reviewer, max_iter, []) do
      {:ok, chunks} ->
        brief = build_brief(topic, domain, chunks, sources)
        {:ok, brief}

      {:error, :max_iterations_reached} ->
        {:error, {:coverage_gap, topic}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Candidate verification
  # ---------------------------------------------------------------------------

  @doc """
  Verify a generated candidate against a research brief.

  Applies rule-based checks in order — no LLM needed for the basic pass.
  Returns `:ok` or `{:error, reason}` where reason is one of:
    - `:missing_evidence`  — none of the brief's facts appear in the candidate
    - `:prohibited_pattern` — candidate contains a pattern the brief forbids
  """
  @spec verify_candidate(map(), Brief.t()) ::
          :ok | {:error, :missing_evidence | :prohibited_pattern | :missing_brief}
  def verify_candidate(_candidate, nil), do: {:error, :missing_brief}

  def verify_candidate(%{messages: messages} = _candidate, %Brief{} = brief) do
    answer_text =
      messages
      |> Enum.filter(&(&1[:role] == "assistant" or &1["role"] == "assistant"))
      |> Enum.map_join(" ", &(&1[:content] || &1["content"] || ""))
      |> String.downcase()

    cond do
      has_prohibited_pattern?(answer_text, brief.prohibited_patterns) ->
        {:error, :prohibited_pattern}

      not has_any_evidence?(answer_text, brief.facts) ->
        {:error, :missing_evidence}

      true ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Brief lifecycle transitions
  # ---------------------------------------------------------------------------

  @doc "Transition a brief to :verified status."
  @spec mark_verified(Brief.t()) :: Brief.t()
  def mark_verified(%Brief{status: :draft} = brief), do: %Brief{brief | status: :verified}
  def mark_verified(%Brief{} = brief), do: brief

  @doc "Transition a brief to :usable_for_generation."
  @spec mark_usable(Brief.t()) :: Brief.t()
  def mark_usable(%Brief{status: :verified} = brief),
    do: %Brief{brief | status: :usable_for_generation}

  def mark_usable(%Brief{} = brief), do: brief

  @doc "Mark a brief as stale."
  @spec mark_stale(Brief.t()) :: Brief.t()
  def mark_stale(%Brief{} = brief), do: %Brief{brief | status: :stale}

  @doc "Archive a brief."
  @spec archive(Brief.t()) :: Brief.t()
  def archive(%Brief{} = brief), do: %Brief{brief | status: :archived}

  # ---------------------------------------------------------------------------
  # Private — loop
  # ---------------------------------------------------------------------------

  defp loop(_original, _query, _conn, _domain, _retriever, _reviewer, 0, _history) do
    {:error, :max_iterations_reached}
  end

  defp loop(original, query, conn, domain, retriever, reviewer, iterations_left, history) do
    chunks = retriever.(conn, query, domain: domain, limit: 5)

    case reviewer.(query, chunks) do
      {:satisfactory, selected} ->
        {:ok, selected}

      {:revise, new_query, reason} ->
        loop(original, new_query, conn, domain, retriever, reviewer, iterations_left - 1, [
          {query, reason} | history
        ])
    end
  end

  # ---------------------------------------------------------------------------
  # Private — brief construction
  # ---------------------------------------------------------------------------

  defp build_brief(topic, domain, chunks, extra_sources) do
    facts = chunks |> Enum.map(& &1.text) |> Enum.uniq()

    chunk_sources =
      chunks
      |> Enum.map(& &1.source_reference)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(fn ref ->
        %{kind: :official_docs, reference: ref, retrieved_at: DateTime.utc_now()}
      end)

    %Brief{
      id: generate_brief_id(topic, domain),
      domain: domain,
      topic: topic,
      facts: facts,
      examples: nil,
      prohibited_patterns: nil,
      sources: chunk_sources ++ extra_sources,
      package_versions: %{},
      created_at: DateTime.utc_now(),
      expires_at: nil,
      status: :draft
    }
  end

  # ---------------------------------------------------------------------------
  # Private — checks
  # ---------------------------------------------------------------------------

  defp has_prohibited_pattern?(_text, nil), do: false
  defp has_prohibited_pattern?(_text, []), do: false

  defp has_prohibited_pattern?(text, patterns) do
    Enum.any?(patterns, fn pattern ->
      String.contains?(text, String.downcase(pattern))
    end)
  end

  defp has_any_evidence?(_text, nil), do: true
  defp has_any_evidence?(_text, []), do: true

  defp has_any_evidence?(text, facts) do
    Enum.any?(facts, fn fact ->
      keywords =
        fact
        |> String.downcase()
        |> String.split(~r/\s+/)
        |> Enum.filter(&(String.length(&1) > 4))

      Enum.any?(keywords, &String.contains?(text, &1))
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — defaults
  # ---------------------------------------------------------------------------

  defp default_retriever(nil, _query, _opts), do: []

  defp default_retriever(conn, query, opts) do
    case Store.search_fts(conn, query, opts) do
      {:ok, chunks} -> chunks
      {:error, _} -> []
    end
  end

  defp default_reviewer(_query, []) do
    {:revise, "broader search", "no results found"}
  end

  defp default_reviewer(_query, chunks) do
    {:satisfactory, chunks}
  end

  defp generate_brief_id(topic, domain) do
    slug = topic |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
    "brief-#{domain}-#{slug}-#{:os.system_time(:millisecond)}"
  end
end
