# Reverie

Elixir-orchestrated LoRA/QLoRA adapter training pipeline for narrow technical domains.

Fine-tunes small, focused adapters that improve a base language model on a specific domain — any domain you define — while combining with retrieval-augmented generation at inference time. Domains are fully configurable: create one with `mix reverie.domain.add --name <name>` and the pipeline handles the rest.

---

## Governing principle

Fine-tuning teaches **stable behaviour**: idiomatic solutions, explanation style, debugging workflow, test habits, correct use of well-established APIs. Retrieval provides **changing evidence**: current docs, package versions, recent changelogs, project-specific source.

Practical order: **prompting → retrieval → adapter training → optional distillation.** An adapter is justified only when it measurably beats a well-prompted, retrieval-augmented base.

---

## Architecture

```
              ┌─────────────────────┐
              │  Domain configuration │  sources, tasks, eval
              └──────────┬──────────┘
                         │
              ┌──────────▼──────────┐
              │  Research / evidence  │  briefs + gap queue
              │  layer (self-refl RAG)│  ← retrieve → review → revise → repeat
              └──────────┬──────────┘
                         │
   ┌─────────────────────▼─────────────────────┐
   │ Phase 1 — Fetch    raw material + manifests + source rights   │
   ├─────────────────────▼─────────────────────┤
   │ Phase 2 — Prepare  synthesis → sandbox → verify → retain     │
   ├─────────────────────▼─────────────────────┤
   │ Phase 3 — Ingest   tokenize → split → dedup → freeze         │
   ├─────────────────────▼─────────────────────┤
   │ Phase 4 — Train    Pythonx/mlx → FLAME GPU → LoRA adapter    │
   ├─────────────────────▼─────────────────────┤
   │ Phase 5 — Evaluate  base / base+RAG / adapter / adapter+RAG  │
   └───────────────────────────────────────────┘
```

**Elixir owns:** fetching, manifests, domain configs, topic queues, brief and retrieval storage (SQLite), generation orchestration, sandbox scheduling, JSONL output, dataset versioning, evaluation orchestration, telemetry, job scheduling.

**Python is restricted to:** loading the training base model, running QLoRA/LoRA, exporting adapter artifacts, and evaluation inference.

---

## Prerequisites

- Elixir ≥ 1.19 / OTP 27
- Docker (sandbox image)
- Python ≥ 3.10 with `mlx-lm` (Apple Silicon) or `bitsandbytes`/`peft` (CUDA)
- S3-compatible object store for artifact versioning (local MinIO works)

```bash
mix deps.get
mix sandbox.build        # build the dataset-gen sandbox image
```

---

## Pipeline walkthrough

### 1. Check status

```bash
mix reverie.status                    # all domains
mix reverie.status --domain <domain>  # single domain
```

### 2. Explore registered domains

```bash
mix reverie.domain                          # list all domains
mix reverie.domain --show <domain>          # full config for a domain
mix reverie.domain --fixtures <domain>      # benchmark fixtures for a domain
```

### 3. Build the knowledge-base corpus

Downloads official documentation, example repositories, and release notes for
the domain. Each domain's `sources/0` declares exactly what to fetch: HexDocs
packages (search index + every module page), GitHub repos (.ex, .exs, .md
files via the tree API), and GitHub release notes. Everything is chunked and
indexed into a per-domain SQLite store for retrieval.

```bash
# Fetch + index in one step (--domain is required for all corpus commands)
mix reverie.corpus.build --domain <domain>

# Recommended: provide a GitHub token to raise API rate limits (60 → 5 000/hr)
mix reverie.corpus.build --domain <domain> --github-token ghp_xxx

# Run phases independently
mix reverie.corpus.build --domain <domain> --phase fetch
mix reverie.corpus.build --domain <domain> --phase index

# Re-index after a corpus format change
mix reverie.corpus.build --domain <domain> --phase index --force
```

Each domain declares its own sources in `sources/0`. For example:

```elixir
def sources do
  %{
    hex_packages: [%{package: "my_lib"}],
    repos: [%{owner: "acme", repo: "my_lib", branch: "main"}],
    releases: [%{owner: "acme", repo: "my_lib", max_releases: 10}]
  }
end
```

### 4. Research and build briefs

```bash
# Quick start — Claude answers directly (no local corpus required)
mix reverie.investigate --domain <domain> --loops 5 --backend cli

# Self-reflective RAG loop against the populated corpus
mix reverie.investigate --domain <domain> --loops 20 --backend api
```

### 5. Run the benchmark baseline

Measure the base model before training to establish a comparison point.

```bash
mix reverie.benchmark --domain <domain> --backend cli
mix reverie.benchmark --domain <domain> --backend api --model claude-haiku-4-5 --out report.json
```

### 6. Generate training candidates

```bash
mix reverie.generate --domain <domain> --count 500
```

Candidates go through: `task spec → brief → teacher generation → parse → static policy → sandbox compile/test → evidence verify → dedup → retain or discard`.

### 7. Freeze a dataset

Deduplicates, splits (train / val / domain test / general regression / safety regression), and writes an immutable snapshot.

```bash
mix reverie.freeze --domain <domain> --version v0.1
```

### 8. Train the adapter

Auto-selects the backend based on hardware (mlx on Apple Silicon, CUDA on GPU).

```bash
mix reverie.train --domain <domain> --dataset v0.1
mix reverie.train --domain <domain> --dataset v0.1 --backend mlx --iters 500
```

### 9. Evaluate

Four-way comparison prevents attributing retrieval gains to fine-tuning:

```
base  /  base+retrieval  /  adapter  /  adapter+retrieval
```

Metrics and promotion criteria are defined per domain. An adapter is promoted only when it improves domain metrics over both the base and retrieval-only baselines, with no unacceptable general regression.

### 10. Serve

Starts an OpenAI-compatible HTTP server for the adapter.

```bash
mix reverie.serve --domain <domain>
mix reverie.serve --domain <domain> --dataset v0.1 --port 8080
```

---

## Defining a domain

Domains are the unit of configuration. There are no built-in domains — every domain is created through the same scaffold:

```bash
mix reverie.domain.add --name <name>
mix reverie.domain.add --name <name> --target-pairs 5000 --expiry-days 120
```

This creates two files and registers the domain in `priv/domains.exs`:

| File | Purpose |
|---|---|
| `lib/domains/<name>.ex` | Config, generation settings, and corpus sources |
| `lib/evaluate/benchmark/fixtures/<name>.ex` | Benchmark prompts for evaluating adapters |

After scaffolding, edit the generated files to:
1. Set `task_weights` to reflect how work in this domain is distributed
2. Add `sources` entries (packages, repos, release histories) for corpus building
3. Write real benchmark fixtures covering the domain's key categories

```bash
mix reverie.domain --show <name>      # verify the config was read correctly
mix reverie.domain --fixtures <name>  # list benchmark fixtures
```

---

## Key safety boundary — sandboxed validation

Generated code is treated as hostile input. It is **never** evaluated in the orchestration BEAM. Sandbox containers run with:

- Network disabled
- Read-only root filesystem, writable tmpfs only
- Non-root user, all capabilities dropped
- Hard memory/CPU/PID limits
- Inner and outer timeouts with explicit kill/remove

```bash
mix sandbox.build   # build or rebuild the sandbox image
```

The CI containment suite verifies: compile-time infinite loop timeout, write-outside-work failure, network connection failure, excessive process creation, excessive allocation termination, plus positive cases (benign compile, passing test, failing test).

---

## Artifact storage

All versioned artifacts are write-once and stored in an S3-compatible bucket:

```
s3://<bucket>/
  <domain>/
    corpus/<corpus-version>/corpus.db        + checksums.json
    datasets/<dataset-version>/...           + snapshot.json
    adapters/<adapter-version>/...           + training_config.json, checksums.json
```

---

## Library stack

| Purpose                         | Library                                 |
|---------------------------------|-----------------------------------------|
| HTTP                            | Req                                     |
| Crawl concurrency               | Broadway                                |
| Durable job workflows           | Oban                                    |
| Data processing                 | Explorer                                |
| Retrieval corpus (SQLite)       | Exqlite + ecto_sqlite3                  |
| S3-compatible artifact storage  | ExAws + ExAws.S3                        |
| Remote GPU burst                | FLAME                                   |
| Python training bridge          | Pythonx                                 |
| Observability                   | Telemetry + TelemetryMetrics            |

---

## Definition of done (first usable adapter)

- Corpus and briefs are auditable; source rights recorded for every item
- Generated code passed isolated sandbox validation
- Splits are frozen and leakage-checked
- Training config is reproducible (fixed seed, pinned versions)
- Adapter is versioned and checksummed
- Domain eval improves over both base and retrieval-only baselines
- Regression checks pass
- At least one approved runtime loads the adapter reliably
