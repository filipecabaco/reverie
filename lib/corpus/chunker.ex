defmodule Corpus.Chunker do
  @max_chunk_chars 2_000
  @min_chunk_chars 60

  @moduledoc """
  Splits raw document content into searchable corpus chunks.

  Chunk strategy auto-detected from the source reference extension:
    .ex / .exs          → function/module-level Elixir chunks
    .md                 → heading sections + fenced code blocks
    .html               → HTML-stripped prose in heading sections
    search.json         → one chunk per documented item (HexDocs format)
    everything else     → paragraph chunks

  All strategies coalesce short pieces (< 2000 chars) to reduce noise and skip
  fragments below 60 chars.
  """

  @type chunk :: %{
          text: String.t(),
          source_reference: String.t(),
          metadata: map()
        }

  @doc """
  Chunk `content` sourced from `source_reference`.
  Returns a list of chunk maps ready for `Corpus.Store.insert_chunk/2`.
  """
  @spec chunk(binary(), String.t()) :: [chunk()]
  def chunk(content, source_reference) when is_binary(content) do
    do_chunk(content, source_reference, detect_kind(source_reference))
  end

  # ---------------------------------------------------------------------------
  # Kind detection
  # ---------------------------------------------------------------------------

  defp detect_kind(ref) do
    cond do
      String.ends_with?(ref, ".ex") or String.ends_with?(ref, ".exs") -> :elixir
      String.ends_with?(ref, ".md") -> :markdown
      String.ends_with?(ref, ".html") -> :html
      String.contains?(ref, "search.json") -> :hex_search_json
      true -> :text
    end
  end

  # ---------------------------------------------------------------------------
  # Chunking strategies
  # ---------------------------------------------------------------------------

  defp do_chunk(content, ref, :elixir) do
    content |> split_elixir() |> build_chunks(ref, :code)
  end

  defp do_chunk(content, ref, :markdown) do
    content |> split_markdown() |> build_chunks(ref, :prose)
  end

  defp do_chunk(content, ref, :html) do
    content |> strip_html() |> split_markdown() |> build_chunks(ref, :prose)
  end

  defp do_chunk(content, ref, :hex_search_json) do
    content
    |> parse_hex_search_json()
    |> Enum.with_index()
    |> Enum.map(fn {{title, text}, idx} ->
      %{
        text: "#{title}\n\n#{text}",
        source_reference: ref,
        metadata: %{chunk_index: idx, kind: :function_doc, title: title}
      }
    end)
  end

  defp do_chunk(content, ref, :text) do
    content |> split_paragraphs() |> build_chunks(ref, :prose)
  end

  # ---------------------------------------------------------------------------
  # Elixir source splitting — before @doc/@moduledoc/@spec or def* keywords
  # ---------------------------------------------------------------------------

  @elixir_split ~r/(?=^\s*(?:@(?:doc|moduledoc|spec|typedoc)|def(?:p|module|macro|macrop|protocol|impl|struct|exception|delegate)?\s))/m

  defp split_elixir(content) do
    @elixir_split
    |> Regex.split(content)
    |> reject_noise()
    |> coalesce(@max_chunk_chars)
  end

  # ---------------------------------------------------------------------------
  # Markdown splitting — on h2+ headings; code blocks kept intact
  # ---------------------------------------------------------------------------

  defp split_markdown(content) do
    Regex.split(~R/(?=^#{2,6} )/m, content)
    |> Enum.flat_map(fn section ->
      Regex.split(~r/```[^\n]*\n[\s\S]*?```/m, section, include_captures: true)
      |> Enum.flat_map(fn part ->
        if String.starts_with?(String.trim(part), "```"),
          do: [String.trim(part)],
          else: split_paragraphs(part)
      end)
    end)
    |> reject_noise()
  end

  # ---------------------------------------------------------------------------
  # Paragraph splitting (fallback)
  # ---------------------------------------------------------------------------

  defp split_paragraphs(content) do
    content
    |> String.split(~r/\n{2,}/)
    |> Enum.map(&String.trim/1)
    |> reject_noise()
    |> coalesce(@max_chunk_chars)
  end

  # ---------------------------------------------------------------------------
  # HTML stripping — removes tags, decodes common entities
  # ---------------------------------------------------------------------------

  defp strip_html(content) do
    content
    |> String.replace(~r/<script[\s\S]*?<\/script>/i, "")
    |> String.replace(~r/<style[\s\S]*?<\/style>/i, "")
    |> String.replace(~r/<\/?(h[1-6])[^>]*>/i, "\n## ")
    |> String.replace(~r/<\/?(p|div|section|article|li|tr)[^>]*>/i, "\n\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", ~s("))
    |> String.replace("&#39;", "'")
    |> String.replace("&nbsp;", " ")
    |> String.replace(~r/ {3,}/, " ")
    |> String.replace(~r/\n{4,}/, "\n\n")
  end

  # ---------------------------------------------------------------------------
  # HexDocs search.json — one chunk per documented item
  # ---------------------------------------------------------------------------

  defp parse_hex_search_json(content) do
    with {:ok, data} <- Jason.decode(content) do
      items = if is_list(data), do: data, else: data["items"] || []

      items
      |> Enum.filter(&is_map/1)
      |> Enum.filter(fn item -> String.length(item["doc"] || "") >= @min_chunk_chars end)
      |> Enum.map(fn item ->
        title = item["title"] || item["ref"] || ""
        {title, item["doc"]}
      end)
    else
      _ -> []
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp reject_noise(parts) do
    Enum.filter(parts, &(String.length(String.trim(&1)) >= @min_chunk_chars))
  end

  defp coalesce(parts, max) do
    parts
    |> Enum.reduce([], fn part, acc ->
      case acc do
        [prev | rest] ->
          if String.length(prev) + String.length(part) + 2 <= max do
            [prev <> "\n\n" <> part | rest]
          else
            [part | acc]
          end

        [] ->
          [part | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp build_chunks(texts, source_reference, default_kind) do
    texts
    |> Enum.with_index()
    |> Enum.map(fn {text, idx} ->
      kind = if String.starts_with?(String.trim(text), "```"), do: :code, else: default_kind

      %{
        text: text,
        source_reference: source_reference,
        metadata: %{chunk_index: idx, kind: kind}
      }
    end)
  end
end
