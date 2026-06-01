defmodule DatasetGen.Parser do
  @moduledoc """
  Strict validation of teacher output before it enters the pipeline.

  Validates shape, required fields, max lengths, and permitted
  code/test_code combinations. Returns a normalised map on success.
  """

  @max_instruction_bytes 4_000
  @max_answer_bytes 16_000
  @max_code_bytes 12_000
  @max_test_code_bytes 8_000

  @type parsed :: %{
          instruction: String.t(),
          answer: String.t(),
          code: String.t() | nil,
          test_code: String.t() | nil
        }

  @spec parse(map()) :: {:ok, parsed()} | {:error, term()}
  def parse(raw) when is_map(raw) do
    with {:ok, instruction} <- require_string(raw, :instruction),
         {:ok, answer} <- require_string(raw, :answer),
         {:ok, code} <- optional_string(raw, :code),
         {:ok, test_code} <- optional_string(raw, :test_code),
         :ok <- check_lengths(instruction, answer, code, test_code),
         :ok <- check_code_test_combo(code, test_code) do
      {:ok,
       %{
         instruction: String.trim(instruction),
         answer: String.trim(answer),
         code: code && String.trim(code),
         test_code: test_code && String.trim(test_code)
       }}
    end
  end

  def parse(_), do: {:error, :not_a_map}

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp require_string(map, key) do
    string_key = to_string(key)
    atom_key = if is_atom(key), do: key, else: String.to_existing_atom(string_key)

    value = Map.get(map, atom_key) || Map.get(map, string_key)

    cond do
      is_nil(value) -> {:error, {:missing_field, key}}
      not is_binary(value) -> {:error, {:wrong_type, key, :string}}
      String.trim(value) == "" -> {:error, {:empty_field, key}}
      true -> {:ok, value}
    end
  end

  defp optional_string(map, key) do
    string_key = to_string(key)
    atom_key = if is_atom(key), do: key, else: String.to_existing_atom(string_key)

    value = Map.get(map, atom_key) || Map.get(map, string_key)

    cond do
      is_nil(value) -> {:ok, nil}
      not is_binary(value) -> {:error, {:wrong_type, key, :string_or_null}}
      String.trim(value) == "" -> {:ok, nil}
      true -> {:ok, value}
    end
  end

  defp check_lengths(instruction, answer, code, test_code) do
    errors =
      []
      |> check_max(instruction, :instruction, @max_instruction_bytes)
      |> check_max(answer, :answer, @max_answer_bytes)
      |> check_max(code, :code, @max_code_bytes)
      |> check_max(test_code, :test_code, @max_test_code_bytes)

    case errors do
      [] -> :ok
      _ -> {:error, {:too_long, errors}}
    end
  end

  defp check_max(errors, nil, _field, _max), do: errors

  defp check_max(errors, value, field, max) do
    if byte_size(value) > max,
      do: [{field, byte_size(value), max} | errors],
      else: errors
  end

  defp check_code_test_combo(nil, test_code) when not is_nil(test_code) do
    {:error, :test_code_without_code}
  end

  defp check_code_test_combo(_code, _test_code), do: :ok
end
