defmodule Research.Coordinator do
  @moduledoc """
  Manages brief retrieval and storage for the dataset generation pipeline.

  Called by `DatasetGen.Worker` to fetch a verified brief before generating
  a training candidate (§8.4). Also used by the serving layer to look up
  current evidence at inference time.
  """

  alias Corpus.Store
  alias Research.{Agent, Brief}

  @doc """
  Return a usable brief for `topic` from the corpus store.

  Policies:
    - `:verified_only` — returns only briefs with status :usable_for_generation
    - `:any`           — returns any non-archived brief, including drafts

  Returns `{:ok, Brief.t()}` or `{:error, :not_found}`.
  """
  @spec verified_brief_for(String.t(), atom(), keyword()) ::
          {:ok, Brief.t()} | {:error, :not_found | term()}
  def verified_brief_for(topic, policy \\ :verified_only, opts \\ []) do
    conn = Keyword.fetch!(opts, :conn)

    status_filter =
      case policy do
        :verified_only -> :usable_for_generation
        :any -> nil
      end

    domain = opts[:domain]

    with {:ok, briefs} <- Store.list_briefs(conn, domain: domain, status: status_filter) do
      match = Enum.find(briefs, &topic_matches?(&1, topic))

      case match do
        nil -> {:error, :not_found}
        brief -> {:ok, brief}
      end
    end
  end

  @doc """
  Save a brief to the corpus store and return it unchanged.
  Useful for chaining: `investigate(...) |> save_brief(conn: conn)`.
  """
  @spec save_brief({:ok, Brief.t()} | Brief.t(), keyword()) ::
          {:ok, Brief.t()} | {:error, term()}
  def save_brief({:ok, %Brief{} = brief}, opts), do: save_brief(brief, opts)

  def save_brief(%Brief{} = brief, opts) do
    conn = Keyword.fetch!(opts, :conn)

    case Store.save_brief(conn, brief) do
      :ok -> {:ok, brief}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Investigate a topic and immediately save the resulting brief.
  Returns `{:ok, Brief.t()}` or `{:error, reason}`.
  """
  @spec investigate_and_save(String.t(), keyword()) :: {:ok, Brief.t()} | {:error, term()}
  def investigate_and_save(topic, opts \\ []) do
    with {:ok, brief} <- Agent.investigate(topic, opts) do
      save_brief(brief, opts)
    end
  end

  @doc """
  Transition an existing brief to :usable_for_generation and persist it.
  Requires the brief to currently be :verified.
  """
  @spec promote(Brief.t(), keyword()) :: {:ok, Brief.t()} | {:error, term()}
  def promote(%Brief{} = brief, opts) do
    promoted = Agent.mark_usable(brief)
    save_brief(promoted, opts)
  end

  @doc "Expire stale briefs in the store, returning the count updated."
  @spec expire_stale(term(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def expire_stale(conn, opts \\ []) do
    domain = opts[:domain]

    with {:ok, briefs} <- Store.list_briefs(conn, domain: domain, status: :usable_for_generation) do
      stale = Enum.filter(briefs, &Brief.stale?/1)

      results =
        Enum.map(stale, fn brief ->
          Store.save_brief(conn, Agent.mark_stale(brief))
        end)

      errors = Enum.filter(results, &match?({:error, _}, &1))

      if errors == [] do
        {:ok, length(stale)}
      else
        {:error, {:partial_failure, errors}}
      end
    end
  end

  defp topic_matches?(%Brief{topic: t}, topic) do
    String.downcase(t) == String.downcase(topic)
  end
end
