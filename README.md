# Reverie

Elixir-orchestrated LoRA/QLoRA adapter training pipeline for narrow technical domains.

Fine-tunes small, focused adapters that improve a base language model on a specific domain — Elixir, Postgres, Supabase, TypeScript, Testing, Security, and Project management — while combining with retrieval-augmented generation at inference time.

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

## Supported domains

| Domain            | Adapter emphasis  | Retrieval emphasis | Target pairs   |
|-------------------|-------------------|--------------------|----------------|
| Elixir            | High              | Medium             | 3,000–8,000    |
| Postgres          | Medium/high       | Medium             | 2,000–5,000    |
| TypeScript        | Medium            | Medium             | 1,000–3,000    |
| Testing           | High              | Low/medium         | 3,000–6,000    |
| Supabase          | Medium            | Very high          | 2,000–5,000    |
| Security          | Conservative      | Very high          | 2,000–5,000    |
| Project management| Style/reasoning   | Medium             | 2,000–5,000    |

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
mix reverie.status                  # all domains
mix reverie.status --domain elixir  # single domain
```

### 2. Explore registered domains

```bash
mix reverie.domain                        # list all
mix reverie.domain --show elixir          # full config
mix reverie.domain --fixtures postgres    # benchmark fixtures
```

### 3. Build the knowledge-base corpus

Downloads official documentation, example repositories, and release notes for
the domain. Each domain's `sources/0` declares exactly what to fetch: HexDocs
packages (search index + every module page), GitHub repos (.ex, .exs, .md
files via the tree API), and GitHub release notes. Everything is chunked and
indexed into a per-domain SQLite store for retrieval.

```bash
# Fetch + index in one step
mix reverie.corpus.build --domain elixir

# Recommended: provide a GitHub token to raise API rate limits (60 → 5 000/hr)
mix reverie.corpus.build --domain elixir --github-token ghp_xxx

# Run phases independently
mix reverie.corpus.build --domain elixir --phase fetch
mix reverie.corpus.build --domain elixir --phase index

# Re-index after a corpus format change
mix reverie.corpus.build --domain elixir --phase index --force
```

The Elixir domain fetches: `elixir`, `mix`, `ex_unit`, `ecto`, `phoenix`,
`phoenix_live_view`, `plug`, `oban`, `req`, `broadway`, `jason`, and others
from HexDocs; source files from eight core repos; and release notes for the
four highest-traffic projects.

To add sources for a domain, implement `sources/0` in the domain module:

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
mix reverie.investigate --domain elixir --loops 5 --backend cli

# Self-reflective RAG loop against the populated corpus
mix reverie.investigate --domain elixir --loops 20 --backend api
```

### 5. Run the benchmark baseline

Measure the base model before training to establish a comparison point.

```bash
mix reverie.benchmark --domain elixir --backend cli
mix reverie.benchmark --domain elixir --backend api --model claude-haiku-4-5 --out report.json
```

### 6. Generate training candidates

```bash
mix reverie.generate --domain elixir --count 500
```

Candidates go through: `task spec → brief → teacher generation → parse → static policy → sandbox compile/test → evidence verify → dedup → retain or discard`.

### 7. Freeze a dataset

Deduplicates, splits (train / val / domain test / general regression / safety regression), and writes an immutable snapshot.

```bash
mix reverie.freeze --domain elixir --version v0.1
```

### 8. Train the adapter

Auto-selects the backend based on hardware (mlx on Apple Silicon, CUDA on GPU).

```bash
mix reverie.train --domain elixir --dataset v0.1
mix reverie.train --domain elixir --dataset v0.1 --backend mlx --iters 500
```

### 9. Evaluate

Four-way comparison prevents attributing retrieval gains to fine-tuning:

```
base  /  base+retrieval  /  adapter  /  adapter+retrieval
```

Objective metrics: parse rate, compile pass-rate, test pass-rate, warning-free rate. Adapter is promoted only when it improves domain metrics over both the base and retrieval-only baselines, with no unacceptable general regression.

### 10. Serve

Starts an OpenAI-compatible HTTP server for the adapter.

```bash
mix reverie.serve --domain elixir
mix reverie.serve --domain elixir --dataset v0.1 --port 8080
```

---

## Adding a new domain

```bash
mix reverie.domain.add --name graphql
```

Scaffolds `lib/domains/graphql.ex` and the benchmark fixtures module, then patches both registries automatically.

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
