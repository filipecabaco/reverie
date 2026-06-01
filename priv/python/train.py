"""
QLoRA domain adapter training script.

Config is read from the CONFIG_JSON variable injected by Pythonx.
Outputs adapter files to config["output_path"] and prints a JSON
result line that Train.Job parses.

smoke=True mode:
  - Skips 4-bit quantization (bitsandbytes not needed on CPU)
  - Uses fp32 instead of bf16
  - max_seq_length=64, max_steps=1
  - Use a tiny model (e.g. facebook/opt-125m) to prove the seam
"""

import hashlib
import json
import os
import sys
from pathlib import Path

import torch
from datasets import Dataset
from peft import LoraConfig, TaskType
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
from trl import SFTConfig, SFTTrainer


def main():
    config = json.loads(CONFIG_JSON)  # injected by Pythonx

    output_path = Path(config["output_path"])
    output_path.mkdir(parents=True, exist_ok=True)

    smoke = config.get("smoke", False)

    tokenizer = AutoTokenizer.from_pretrained(config["base_model"])
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    if smoke:
        model = AutoModelForCausalLM.from_pretrained(
            config["base_model"],
            torch_dtype=torch.float32,
        )
    else:
        bnb_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type=config.get("quantization", "nf4"),
            bnb_4bit_use_double_quant=config.get("double_quant", True),
            bnb_4bit_compute_dtype=torch.bfloat16,
        )
        model = AutoModelForCausalLM.from_pretrained(
            config["base_model"],
            quantization_config=bnb_config,
            device_map="auto",
        )

    lora_config = LoraConfig(
        task_type=TaskType.CAUSAL_LM,
        r=config.get("lora_rank", 16),
        lora_alpha=config.get("lora_alpha", 32),
        lora_dropout=config.get("lora_dropout", 0.05),
        target_modules=config.get("target_modules", "all-linear"),
        bias="none",
    )

    records = load_jsonl(config["dataset_path"])

    def format_messages(example):
        text = tokenizer.apply_chat_template(
            example["messages"], tokenize=False, add_generation_prompt=False
        )
        return {"text": text}

    dataset = Dataset.from_list(records).map(format_messages)

    training_args = SFTConfig(
        output_dir=str(output_path),
        num_train_epochs=1 if smoke else config.get("num_epochs", 2),
        max_steps=1 if smoke else -1,
        per_device_train_batch_size=1 if smoke else config.get("per_device_batch_size", 4),
        learning_rate=float(config.get("learning_rate", 2e-4)),
        max_seq_length=64 if smoke else config.get("max_seq_length", 2048),
        seed=config.get("seed", 42),
        save_strategy="no",
        logging_steps=1,
        gradient_checkpointing=False if smoke else config.get("gradient_checkpointing", True),
        fp16=False,
        bf16=False if smoke else (config.get("compute_dtype") == "bfloat16"),
        report_to="none",
        dataset_text_field="text",
    )

    trainer = SFTTrainer(
        model=model,
        args=training_args,
        train_dataset=dataset,
        peft_config=lora_config,
    )

    train_result = trainer.train()

    trainer.save_model(str(output_path))

    write_checksums(output_path)

    metrics = {
        "train_loss": train_result.training_loss,
        "train_steps": int(train_result.global_step),
    }

    (output_path / "train_metrics.json").write_text(json.dumps(metrics, indent=2))

    print(json.dumps({"status": "ok", "metrics": metrics}))


def load_jsonl(dataset_path):
    train_file = Path(dataset_path) / "train.jsonl"
    records = []
    with open(train_file) as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    return records


def write_checksums(output_path):
    checksums = {}
    for pattern in ["*.json", "*.safetensors", "*.bin"]:
        for f in sorted(output_path.glob(pattern)):
            if f.name == "checksums.json":
                continue
            checksums[f.name] = hashlib.sha256(f.read_bytes()).hexdigest()
    (output_path / "checksums.json").write_text(json.dumps(checksums, indent=2))


if __name__ == "__main__":
    main()
