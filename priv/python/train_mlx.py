"""
LoRA fine-tuning via MLX-LM for Apple Silicon (M1/M2/M3/M4).

Config is read from CONFIG_JSON env var. Requires:
    pip install mlx-lm

Usage (via mix reverie.train --backend mlx):
    CONFIG_JSON='{"base_model":"...","dataset_path":"...","output_path":"..."}' python train_mlx.py
"""

import json
import os
import sys
import subprocess
from pathlib import Path


def main():
    config = json.loads(os.environ["CONFIG_JSON"])

    dataset_path = Path(config["dataset_path"])
    output_path = Path(config["output_path"])
    output_path.mkdir(parents=True, exist_ok=True)

    base_model = config["base_model"]
    iters = config.get("iters", 1000)
    batch_size = config.get("batch_size", 4)
    lora_layers = config.get("lora_layers", 16)
    learning_rate = config.get("learning_rate", 1e-4)
    seed = config.get("seed", 42)

    # Convert our JSONL format to MLX-LM's expected format
    mlx_data_dir = output_path / "mlx_data"
    mlx_data_dir.mkdir(exist_ok=True)
    convert_dataset(dataset_path, mlx_data_dir)

    valid_file = mlx_data_dir / "valid.jsonl"
    valid_count = sum(1 for _ in open(valid_file)) if valid_file.exists() else 0
    val_batches = valid_count // batch_size
    if val_batches == 0:
        print(f"  Warning: only {valid_count} validation examples (need {batch_size}); skipping validation.", flush=True)

    # Run mlx_lm.lora
    cmd = [
        sys.executable, "-m", "mlx_lm.lora",
        "--model", base_model,
        "--train",
        "--data", str(mlx_data_dir),
        "--iters", str(iters),
        "--batch-size", str(batch_size),
        "--num-layers", str(lora_layers),
        "--learning-rate", str(learning_rate),
        "--seed", str(seed),
        "--adapter-path", str(output_path / "adapters"),
        "--val-batches", str(val_batches),
    ]

    print(f"Running: {' '.join(cmd)}", flush=True)
    result = subprocess.run(cmd)

    if result.returncode != 0:
        print(json.dumps({"status": "error", "exit_code": result.returncode}))
        sys.exit(result.returncode)

    print(json.dumps({"status": "ok", "adapter_path": str(output_path / "adapters")}))


def convert_dataset(dataset_path: Path, out_dir: Path):
    """
    Convert our {messages: [...], meta: {...}} JSONL format to MLX-LM's
    {messages: [...]} format, which it uses for chat fine-tuning.
    """
    for split in ["train", "validation", "test"]:
        src = dataset_path / f"{split}.jsonl"
        dst_name = "valid.jsonl" if split == "validation" else f"{split}.jsonl"
        dst = out_dir / dst_name

        if not src.exists():
            continue

        with open(src) as f_in, open(dst, "w") as f_out:
            for line in f_in:
                line = line.strip()
                if not line:
                    continue
                record = json.loads(line)
                # MLX-LM expects {"messages": [...]} — strip our meta field
                mlx_record = {"messages": record["messages"]}
                f_out.write(json.dumps(mlx_record) + "\n")

        count = sum(1 for _ in open(dst))
        print(f"  {split}: {count} records → {dst_name}", flush=True)


if __name__ == "__main__":
    main()
