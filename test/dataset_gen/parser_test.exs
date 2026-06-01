defmodule DatasetGen.ParserTest do
  use ExUnit.Case, async: true

  alias DatasetGen.Parser

  describe "parse/1 — happy path" do
    test "accepts a complete candidate with code and test_code" do
      raw = %{
        instruction: "Implement Stack.push/2",
        answer: "Here is the implementation:\n```elixir\ndef push(stack, item)...\n```",
        code: "defmodule Stack do\n  def push(s, i), do: [i | s]\nend",
        test_code:
          "defmodule StackTest do\n  use ExUnit.Case\n  test \"push\" do\n    assert Stack.push([], 1) == [1]\n  end\nend"
      }

      assert {:ok, parsed} = Parser.parse(raw)
      assert parsed.instruction == raw.instruction
      assert parsed.answer == raw.answer
      assert parsed.code == raw.code
      assert parsed.test_code == raw.test_code
    end

    test "accepts a candidate with only instruction and answer" do
      raw = %{
        instruction: "Explain GenServer",
        answer: "GenServer is...",
        code: nil,
        test_code: nil
      }

      assert {:ok, %{code: nil, test_code: nil}} = Parser.parse(raw)
    end

    test "accepts a candidate with code but no test_code" do
      raw = %{
        instruction: "Fix this",
        answer: "Fixed.",
        code: "defmodule M do\nend",
        test_code: nil
      }

      assert {:ok, %{code: code, test_code: nil}} = Parser.parse(raw)
      assert is_binary(code)
    end

    test "accepts string keys from JSON decode" do
      raw = %{
        "instruction" => "Explain",
        "answer" => "It is...",
        "code" => nil,
        "test_code" => nil
      }

      assert {:ok, _} = Parser.parse(raw)
    end

    test "trims whitespace from fields" do
      raw = %{instruction: "  Implement  ", answer: "  Here.  ", code: nil, test_code: nil}
      assert {:ok, %{instruction: "Implement", answer: "Here."}} = Parser.parse(raw)
    end
  end

  describe "parse/1 — required field validation" do
    test "returns error when instruction is missing" do
      raw = %{answer: "Something", code: nil, test_code: nil}
      assert {:error, {:missing_field, :instruction}} = Parser.parse(raw)
    end

    test "returns error when answer is missing" do
      raw = %{instruction: "Question", code: nil, test_code: nil}
      assert {:error, {:missing_field, :answer}} = Parser.parse(raw)
    end

    test "returns error when instruction is empty string" do
      raw = %{instruction: "   ", answer: "Something", code: nil, test_code: nil}
      assert {:error, {:empty_field, :instruction}} = Parser.parse(raw)
    end

    test "returns error when answer is empty string" do
      raw = %{instruction: "Question", answer: "", code: nil, test_code: nil}
      assert {:error, {:empty_field, :answer}} = Parser.parse(raw)
    end
  end

  describe "parse/1 — code/test_code combination" do
    test "returns error when test_code present but code is nil" do
      raw = %{
        instruction: "Write tests",
        answer: "Here are tests.",
        code: nil,
        test_code: "defmodule T do\n  use ExUnit.Case\nend"
      }

      assert {:error, :test_code_without_code} = Parser.parse(raw)
    end
  end

  describe "parse/1 — length limits" do
    test "returns error when instruction exceeds max bytes" do
      raw = %{
        instruction: String.duplicate("x", 5_000),
        answer: "Short.",
        code: nil,
        test_code: nil
      }

      assert {:error, {:too_long, _}} = Parser.parse(raw)
    end

    test "returns error when answer exceeds max bytes" do
      raw = %{
        instruction: "Question",
        answer: String.duplicate("x", 17_000),
        code: nil,
        test_code: nil
      }

      assert {:error, {:too_long, _}} = Parser.parse(raw)
    end
  end

  describe "parse/1 — non-map input" do
    test "returns error for non-map input" do
      assert {:error, :not_a_map} = Parser.parse("not a map")
      assert {:error, :not_a_map} = Parser.parse(nil)
      assert {:error, :not_a_map} = Parser.parse([1, 2])
    end
  end
end
