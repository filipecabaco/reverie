defmodule Evaluate.Benchmark.FixtureGenerator do
  @moduledoc """
  Generates benchmark fixture candidates from research briefs.

  Generated fixtures start as `scoreable: false` drafts. A human (or later,
  an automated judge) reviews them and may add `test_code` and flip `scoreable`
  before they are promoted to the benchmark.

  The prompts are template-based — no model is needed at this stage. Model-driven
  synthesis comes later in the dataset generation pipeline (Phase 2).
  """

  alias Evaluate.Benchmark.Fixture
  alias Research.Brief

  @default_task_types [:explain, :implement, :identify]

  @doc """
  Generates fixture candidates from a verified brief.
  Returns an empty list if the brief is not usable.
  """
  @spec from_brief(Brief.t(), keyword()) :: [Fixture.t()]
  def from_brief(%Brief{} = brief, opts \\ []) do
    if Brief.usable?(brief) do
      task_types = Keyword.get(opts, :task_types, @default_task_types)
      Enum.flat_map(task_types, &build_fixture(brief, &1))
    else
      []
    end
  end

  # ---------------------------------------------------------------------------
  # Task builders
  # ---------------------------------------------------------------------------

  defp build_fixture(brief, :explain) do
    [
      %Fixture{
        id: fixture_id(brief, :explain),
        category: infer_category(brief),
        difficulty: :medium,
        prompt: explain_prompt(brief),
        test_code: nil,
        tags: brief_tags(brief) ++ [:explanation, :generated],
        scoreable: false,
        sandbox_profile: nil
      }
    ]
  end

  defp build_fixture(%Brief{examples: examples} = brief, :implement)
       when is_list(examples) and examples != [] do
    [
      %Fixture{
        id: fixture_id(brief, :implement),
        category: infer_category(brief),
        difficulty: :medium,
        prompt: implement_prompt(brief),
        test_code: nil,
        tags: brief_tags(brief) ++ [:implementation, :generated],
        scoreable: false,
        sandbox_profile: nil
      }
    ]
  end

  defp build_fixture(_brief, :implement), do: []

  defp build_fixture(brief, :identify) do
    [
      %Fixture{
        id: fixture_id(brief, :identify),
        category: infer_category(brief),
        difficulty: :easy,
        prompt: identify_prompt(brief),
        test_code: nil,
        tags: brief_tags(brief) ++ [:identification, :generated],
        scoreable: false,
        sandbox_profile: nil
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Prompt templates
  # ---------------------------------------------------------------------------

  defp explain_prompt(%Brief{topic: topic, facts: facts, sources: sources}) do
    facts_text = facts |> Enum.take(5) |> Enum.map_join("\n", &"- #{&1}")
    source_text = sources |> Enum.take(2) |> Enum.map_join(", ", & &1.reference)

    """
    Explain **#{topic}** clearly and accurately.

    Cover all of the following points:
    #{facts_text}

    Include a concrete example. Cite behaviour that is version-specific where relevant.

    Sources this answer should be consistent with: #{source_text}
    """
  end

  defp implement_prompt(%Brief{topic: topic, facts: facts, examples: examples}) do
    facts_text = facts |> Enum.take(3) |> Enum.map_join("\n", &"- #{&1}")

    example_text =
      examples
      |> Enum.take(2)
      |> Enum.map_join("\n\n", fn ex ->
        case ex do
          %{description: d} -> d
          %{"description" => d} -> d
          other -> inspect(other)
        end
      end)

    """
    Based on the following context about **#{topic}**:

    Key facts:
    #{facts_text}

    Reference examples:
    #{example_text}

    Implement a working solution that demonstrates correct usage of #{topic}.
    Your implementation must be consistent with the facts above.
    """
  end

  defp identify_prompt(%Brief{topic: topic, facts: facts, prohibited_patterns: prohibited}) do
    facts_text = facts |> Enum.take(4) |> Enum.map_join("\n", &"- #{&1}")

    prohibited_text =
      case prohibited do
        nil ->
          ""

        [] ->
          ""

        patterns ->
          "\n\nAvoid these common mistakes:\n" <> Enum.map_join(patterns, "\n", &"- #{&1}")
      end

    """
    What are the key considerations when working with **#{topic}**?

    Context:
    #{facts_text}
    #{prohibited_text}

    Identify the most important points a developer must understand to use #{topic} correctly.
    Be specific — avoid generic advice.
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp fixture_id(%Brief{domain: domain, topic: topic, id: brief_id}, task_type) do
    slug = topic |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
    "#{domain}-gen-#{slug}-#{task_type}-#{String.slice(brief_id, 0, 8)}"
  end

  defp infer_category(%Brief{topic: topic}) do
    topic
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
    |> String.to_atom()
  end

  defp brief_tags(%Brief{domain: domain, topic: topic}) do
    slug = topic |> String.downcase() |> String.replace(~r/\s+/, "_") |> String.to_atom()
    [domain, slug]
  end
end
