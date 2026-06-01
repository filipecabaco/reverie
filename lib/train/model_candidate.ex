defmodule Train.ModelCandidate do
  @moduledoc """
  Describes a base model candidate for evaluation.

  Each candidate must pass all gates before being selected:
  strong code performance, acceptable Elixir baseline, suitable licence,
  QLoRA support, adapter export compatibility, serving compatibility,
  and memory fit (§1.3).
  """

  @enforce_keys [:id, :name, :params_b, :license, :commercial_ok]
  defstruct [
    :id,
    :name,
    :params_b,
    :license,
    :commercial_ok,
    qlora_compatible: true,
    peft_target_modules: "all-linear",
    estimated_vram_4bit_gb: nil,
    chat_template: :chatml,
    notes: nil
  ]

  @type license ::
          :apache2
          | :mit
          | :llama3
          | :mistral
          | :deepseek
          | :qwen
          | :gemma
          | :proprietary

  @type chat_template :: :chatml | :llama3 | :mistral | :phi3 | :gemma | :unknown

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          params_b: float(),
          license: license(),
          commercial_ok: boolean(),
          qlora_compatible: boolean(),
          peft_target_modules: String.t() | [String.t()],
          estimated_vram_4bit_gb: float() | nil,
          chat_template: chat_template(),
          notes: String.t() | nil
        }

  @doc "The shortlisted candidates for the Elixir domain adapter bake-off."
  @spec shortlist() :: [t()]
  def shortlist do
    [
      %__MODULE__{
        id: "Qwen/Qwen2.5-Coder-7B-Instruct",
        name: "Qwen2.5-Coder-7B",
        params_b: 7.6,
        license: :qwen,
        commercial_ok: true,
        qlora_compatible: true,
        peft_target_modules: "all-linear",
        estimated_vram_4bit_gb: 5.5,
        chat_template: :chatml,
        notes:
          "Strong code benchmark results; good instruction following; Qwen licence permits commercial use"
      },
      %__MODULE__{
        id: "deepseek-ai/deepseek-coder-7b-instruct-v1.5",
        name: "DeepSeek-Coder-7B-v1.5",
        params_b: 6.9,
        license: :deepseek,
        commercial_ok: true,
        qlora_compatible: true,
        peft_target_modules: "all-linear",
        estimated_vram_4bit_gb: 5.2,
        chat_template: :chatml,
        notes: "Consistent top performer on code benchmarks; MIT-style licence"
      },
      %__MODULE__{
        id: "codellama/CodeLlama-7b-Instruct-hf",
        name: "CodeLlama-7B-Instruct",
        params_b: 7.0,
        license: :llama3,
        commercial_ok: true,
        qlora_compatible: true,
        peft_target_modules: "all-linear",
        estimated_vram_4bit_gb: 5.3,
        chat_template: :llama3,
        notes: "Meta licence; strong baseline for code; infra-proven with bitsandbytes + PEFT"
      }
    ]
  end

  @doc "Return candidates that pass the hard gates (commercial OK + QLoRA compatible)."
  @spec eligible?(t()) :: boolean()
  def eligible?(%__MODULE__{commercial_ok: true, qlora_compatible: true}), do: true
  def eligible?(%__MODULE__{}), do: false
end
