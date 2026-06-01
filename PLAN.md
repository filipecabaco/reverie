# Reverie — Domain Adapter Training Platform

Elixir-orchestrated LoRA/QLoRA pipeline for narrow technical domains.
First domain: **Elixir** · Later: Postgres, Supabase, TypeScript, Testing, Security, Project management.

---

## Governing principle

Fine-tuning teaches **stable behaviour** (idiomatic solutions, explanation style, debugging workflow, test habits, repo conventions, correct use of well-established APIs). Retrieval provides **changing evidence** (current docs, package versions, recent changelogs, updated Supabase behaviour, current security guidance, project-specific source).

Practical order: **prompting → retrieval → adapter training → optional distillation.** An adapter is justified only when it measurably beats a well-prompted, retrieval-augmented base.

---

## Architecture

```
              ┌─────────────────────┐
              │ Domain configuration │  sources, tasks, eval
              └──────────┬──────────┘
                         │
              ┌──────────▼──────────┐
              │ Research / evidence  │  briefs + gap queue
              │ layer (self-refl RAG)│  ← iterative retrieve–review–revise
              └──────────┬──────────┘
                         │
   ┌─────────────────────▼─────────────────────┐
   │ Phase 1 — Fetch    raw material + manifests + source rights │
   ├─────────────────────▼─────────────────────┤
   │ Phase 2 — Prepare  synthesis → sandbox → verify → retain    │
   ├─────────────────────▼─────────────────────┤
   │ Phase 3 — Ingest   tokenize → split → dedup → freeze        │
   ├─────────────────────▼─────────────────────┤
   │ Phase 4 — Train    Pythonx → FLAME GPU → QLoRA adapter      │
   ├─────────────────────▼─────────────────────┤
   │ Phase 5 — Evaluate domain tests + general regressions       │
   ├─────────────────────▼─────────────────────┤
   │ Serving compatibility gate  runtime + quant + adapter load  │
   └───────────────────────────────────────────┘
```

**Elixir owns:** fetching, manifests, domain configs, topic queues, brief + retrieval storage (SQLite), generation orchestration, sandbox scheduling, JSONL output, dataset versioning, evaluation orchestration, telemetry, job scheduling, product-facing APIs.

**Python is restricted to:** loading the training model + canonical tokenizer, running QLoRA, exporting adapter artifacts, and optionally temporary evaluation inference until the serving runtime is chosen.

**Libraries:** Req (HTTP), Broadway (crawl concurrency), Oban (durable workflows), Explorer (data), Exqlite + ecto_sqlite3 (retrieval store), Livebook (experiments), Telemetry + Prometheus/Grafana, FLAME (remote burst), Pythonx (training bridge).

---

## Non-negotiable constraints

- **One base hosting several adapters is a serving-runtime capability**, not automatic. Do not commit to pure-Elixir adapter serving until base model, quantization format, and adapter operations are demonstrated together.
- **QLoRA training format ≠ quantized serving format.** Training uses 4-bit (NF4) frozen base. Inference may use GGUF/Q4_K_M. Validate these artifacts separately.
- **Model selection is an empirical gate.** A base must pass: strong code performance; acceptable Elixir baseline; suitable licence; QLoRA support; adapter export compatibility; serving compatibility; memory fit.
- **Generated Elixir is hostile input.** It must never be compiled or evaluated in the orchestration BEAM. The sandbox is the safety boundary of the whole system.
- **Source legality and dataset quality are distinct gates.** Every fetched item records: source type, location, fetch timestamp, licence/terms, training-allowed, redistribution-allowed, personal/sensitive-data flag, version.
- **Each domain owns one authoritative RAG corpus.** It grounds both training-data synthesis and inference-time retrieval. Domains never share a store.

---

## Artifact storage

All durable, versioned artifacts live in a single S3-compatible object store (provider-agnostic via S3 API; `ExAws.S3` or a `Req` client in Elixir). Write-once and immutable — a change is always a new version, never an in-place mutation.

```
s3://<bucket>/
  <domain>/
    corpus/<corpus-version>/corpus.db        + checksums.json
    datasets/<dataset-version>/...           + snapshot.json
    adapters/<adapter-version>/...           + training_config.json, checksums.json
```

The embedding model is part of corpus identity — bake it into the corpus version (e.g. `elixir-corpus-v3-bge-small-en`). Changing the embedder forces a re-embed and a new corpus version.

---

## Research and evidence layer

**Evidence hierarchy:** 1) official language/library docs; 2) official source repos + changelogs; 3) maintainer discussions / release notes; 4) high-quality community examples (task discovery only unless verified); 5) general web (gap discovery, never sole authority).

**Self-reflective RAG loop** (both evidence gathering and inference-time retrieval):

```
query
  → retrieve top-k
  → REVIEW (LLM critiques: relevant? useful? sufficient? current?)
  → satisfactory?
        yes → use evidence
        no  → REVISE query from the critique → retrieve again
  → repeat until satisfactory OR max_iterations reached
```

Cap iterations (e.g. 3). If the loop exits unsatisfied, mark the topic as a coverage gap rather than fabricating.

**Brief lifecycle:** `draft → verified → usable_for_generation → stale → archived`

**Retrieval store:** one SQLite database per domain (`data/<domain>/corpus.db`). FTS5 for text retrieval, `sqlite-vec` extension for vector retrieval. Hybrid retrieval (FTS5 + vector) is the recommended default. Build once centrally, distribute as a versioned read-only artifact to each node.

**Two rights-filtered views on one store:**
- **training view** — rows where `training_allowed`
- **reference view** — rows where reference/redistribution is permitted

---

## Phase 0 — Foundations and decision gates

**Objective:** prove the risky seams before building a large corpus.

**Deliverables:**
- [ ] Candidate base-model shortlist
- [ ] Training-compatibility spike (Pythonx + FLAME)
- [ ] Minimal adapter export + temporary inference path
- [ ] Canonical tokenizer decision
- [ ] Sandbox proof-of-containment
- [ ] Dataset manifest format
- [ ] Evaluation fixture format

**Base-model bake-off:** 100–200 prompt Elixir benchmark (pattern matching, GenServer design, supervision, Ecto queries/migrations, Plug/Phoenix, ExUnit, debugging, OTP reasoning, Postgres integration). Measure per candidate: compile pass-rate, test pass-rate, explanation quality, context behaviour, memory, training compatibility, adapter inference compatibility.

**First smoke train:** ~20–50 hand-authored Elixir pairs, one candidate model, short sequence length, minimal epochs, adapter export, reload in temporary inference runtime, base-vs-adapter comparison. This is a seam test, not a useful model.

**Done when:** `dataset → tokenizer → QLoRA train → adapter export → adapter reload → evaluation prompt` works end to end **and** the sandbox has demonstrably contained malicious compile-time behaviour.

---

## Phase 1 — Fetch and provenance

**Objective:** auditable raw corpus + evidence store.

**Source categories (default status):**
- Official Elixir docs — candidate
- Official Hex docs — candidate
- Permissively-licensed repos — candidate after licence review
- Changelogs/release notes — retrieval/evidence first
- GitHub issues — research only by default
- Forum content — discovery only until rights reviewed
- Internally-authored examples — preferred

**Manifest entry fields:** id, domain, source_kind, reference, local_path, fetched_at, detected_license, terms_review, training_allowed, redistribution_allowed, contains_personal_data, content_hash, version_context, notes.

**Data layout:**
```
data/<domain>/
  raw/{official_docs,official_repos,release_notes,discovered}/
  briefs/
  corpus.db
  manifests/raw.jsonl
  generated/  datasets/  evaluations/  artifacts/
```

**Pipeline (Broadway):** discover reference → fetch → hash → categorize → apply source-rights policy → write raw artifact → write manifest. Do not convert to training data inside the fetch pipeline.

**Done when:** raw corpus on disk/object storage; every item has a manifest entry; briefs can reference original sources; disallowed/unresolved sources are segregated; pipeline resumes without re-downloading duplicates.

---

## Phase 2 — Prepare, synthesise, validate

**Objective:** instruction pairs that are attributable, structured, deduplicated, executable where code is present, current relative to their brief, and suitable for eval + training.

**Candidate lifecycle:**
```
task spec → attach verified brief → teacher generation → strict parse
  → static policy checks → isolated compile/test sandbox
  → one bounded repair (if enabled) → evidence verification
  → optional quality judge → dedup → retain or discard
```

**Task types (Elixir):** Implement, Debug, Refactor, Test, Explain, Review. Code-producing tasks should dominate because they support objective compile/test gates.

**Output schema:**
```json
{
  "messages": [{"role": "user", "content": "..."}, {"role": "assistant", "content": "..."}],
  "meta": {
    "id": "sha256",
    "domain": "elixir",
    "task_type": "debug",
    "topic": "genserver",
    "difficulty": "medium",
    "source_kind": "synthetic_grounded",
    "brief_id": "brief-sha256",
    "compiled": true,
    "tests_passed": true,
    "judge_score": 4.5,
    "generator_model": "...",
    "generated_at": "..."
  }
}
```

**Concurrency limits (keep independent):**
- Teacher calls — API rate + budget
- Sandbox runs — CPU/RAM/container startup, enforce `sandbox_slots` via a pool
- Writes — serial/batched
- Research fetching — source limits/politeness
- Judge calls — cost-controlled, sampled

---

## Mandatory safety boundary — sandboxed validation

**Threat model:** any candidate may at compile time loop forever, exhaust memory, spawn processes recursively, delete files, read secrets, open network connections, invoke shells, or exploit dependencies.

**Required containment:** disposable container/microVM; network disabled; read-only root FS; writable tmpfs only; read-only input mount; no secrets; non-root user; drop all capabilities; no-new-privileges; hard memory/CPU/PID limits; inner + outer timeouts; explicit kill/remove after timeout; pre-baked dependencies only.

**Critical rule:** never write generated source into a host project that shares credentials, dependency caches, build output, or the Docker socket.

**Sandbox image policy:**
```
dataset-gen-sandbox:stdlib  · :ecto  · :plug  · :phoenix
```

**Containment test suite (CI + on image/runtime changes):** compile-time infinite loop (timeout + destroy); attempt to delete mounted source (host unchanged); write outside `/work` (fails); network connection (fails); excessive process creation (PID cap holds); excessive allocation (terminated); plus positive cases — benign module compiles, passing test recorded, failing test recorded.

---

## Phase 3 — Ingest and freeze

**Canonical tokenizer rule:** use the tokenizer of the exact training base model. Acceptable: call the Python tokenizer via Pythonx during ingestion, compute stats in Python and return summaries, or use an Elixir tokenizer only after verifying token-for-token equivalence on a representative sample. Never assume parity from a shared family name.

**Required splits:** Train; Validation; Domain test (held-out Elixir benchmark); General regression; Safety regression; Current-facts/RAG slice.

**Leakage prevention:** deduplicate before splitting — normalised instruction hash, code-normalisation hash, near-duplicate similarity, topic/source/brief grouping. Variants from the same seed or brief must not split across train/test.

**Done when:** every split frozen; leakage checks pass; token-length distributions stored; dataset hash recorded; training consumes the immutable snapshot, not mutable working files.

---

## Phase 4 — Train the adapter

**Starting QLoRA config:**
- 4-bit base (NF4), double-quant where supported, BF16 compute where available
- Target all linear layers (attention + MLP projections)
- Rank 16 or 32 (evaluate before raising), alpha ≈ rank or 2× rank, dropout ~0.05
- 1–3 epochs, fixed recorded seed

**Execution boundary:** Elixir job resolves an immutable snapshot → starts a FLAME GPU runner → invokes one Pythonx training op → streams coarse progress → **uploads the adapter package to S3 before terminating the runner** → returns artifact refs + metrics → releases the runner.

**Artifact package:**
```
artifacts/elixir/adapter-v0.1.0/
  adapter_config.json  adapter_model.safetensors  training_config.json
  dataset_snapshot.json  eval_summary.json  base_model.json  tokenizer.json  checksums.json
```

**Done when:** the adapter reloads in an evaluation runtime and evaluates reproducibly against the frozen test suite.

---

## Phase 5 — Evaluate before serving

**Required four-way comparison per test prompt:**
```
base  /  base+retrieval  /  adapter  /  adapter+retrieval
```
This prevents crediting retrieval gains to fine-tuning.

**Objective Elixir metrics:** parse rate, compile pass-rate, test pass-rate, warning-free pass-rate, repair rate, timeout rate.

**Qualitative (rubric):** idiomatic Elixir; correct OTP reasoning; no unsafe compile/eval advice; clarity; concision; no invented APIs; correct uncertainty handling; correct use of retrieval evidence.

**Regression checks:** general code tasks; basic reasoning; non-Elixir explanations; refusal behaviour for unsafe requests; ability to answer with retrieval when the answer changed after training.

**Promotion gate:** usable only when it improves domain metrics over base; no unacceptable general regression; no increase in unsafe-code behaviour; compatible with ≥1 approved inference runtime; recorded dataset + artifact lineage.

---

## Serving strategy

**Inference flow:**
```
Phoenix/Elixir routing
  → select domain adapter
  → retrieve evidence from node-local read-only SQLite replica
    via self-reflective RAG loop (retrieve → review → revise → re-retrieve, capped)
  → call inference runtime with base + selected adapter
  → record evaluation/telemetry
```

**Two serving tracks:**
- **Verified adapter-serving runtime** — required first, for correct evaluation and early product behaviour
- **Pure-Elixir serving spike** — optional until Bumblebee/Nx loading + quantization + adapter execution are proven

**Serving compatibility matrix (verify before committing):** load base; load adapter unmerged; load multiple adapters; per-request adapter switch under concurrency; quantized base meets memory budget; trained adapter loads; tokenizer parity; retrieval context within token budget; observability.

---

## Multi-domain strategy

| Domain | Adapter emphasis | Retrieval emphasis | Initial retained pairs |
|---|---|---|---|
| Elixir | High | Medium | 3,000–8,000 |
| Postgres | Medium/high | Medium | 2,000–5,000 |
| TypeScript | Medium | Medium | 1,000–3,000 |
| Testing | High | Low/medium | 3,000–6,000 |
| Supabase | Medium | Very high | 2,000–5,000 |
| Security | Conservative | Very high | 2,000–5,000 |
| Project management | Style/reasoning | Medium | 2,000–5,000 |

**Domain warnings:**
- *Supabase* — stays retrieval-heavy; product surface changes fast; adapter focuses on solution structure, SQL/RLS reasoning, migration discipline, not memorising current behaviour.
- *Security* — stricter source policy, safe defensive tasks, refusal/escalation tests, mandatory human review before release.
- *Project management* — shapes style/decision frameworks but is hard to validate mechanically; start only after code-domain pipeline is reliable.

---

## Build order (recommended)

- [x] **1. Repo structure** — `lib/{research,corpus,dataset_gen,ingest,train,evaluate,serving_compat}/`, `data/`, `priv/`, `test/`
- [x] **2. Sandbox first** — image, `DatasetGen.Sandbox`, CI containment tests, stdlib profile only
- [x] **3. Tiny human benchmark** — fixtures for all 7 domains (Elixir, Postgres, Supabase, TypeScript, Testing, Security, PM), executable sandbox-scored tests where possible, domain behaviour + per-domain modules, scoring harness
- [x] **4. Prove the training seam** — Pythonx deps, FLAME GPU runner, tiny JSONL, one smoke-train adapter, one reload + evaluation
- [x] **5. Select the base model** — run benchmark + compatibility checks; choose on evidence
- [x] **6. Manifests + fetchers** — corpus manifest, source-policy enforcement, official-source fetchers, hash-based resumption
- [x] **7. Minimal research briefs** — one verified brief format, one authoritative-source investigation workflow (self-reflective loop), retrieval storage, expiry/version logic
- [x] **8. Generation + parsing** — strict schema, parser, one generation flow, no concurrency
- [x] **9. Single-candidate validation** — spec → brief → generation → parse → sandbox → evidence verify → record
- [x] **10. Broadway + resumability** — generation rate limiting, independent sandbox capacity gate, JSONL batching, dedup, checkpointing, telemetry
- [x] **11. Dataset v0.1 (any domain)** — frozen train/val/test/regression splits, source + brief hashes, quality review, distribution reports; domain-agnostic builder parameterized by ratios, filters, and seed
- [x] **12. Train + evaluate (any domain)** — artifact verification, four-way metrics (base/base+RAG/adapter/adapter+RAG), serving compatibility checklist, promotion/rejection gate with :promote/:reject/:incomplete decisions
- [x] **13. Parameterise + run Postgres** — second domain proves reusability; zero core-pipeline changes required

---

## Definition of done (first usable adapter)

All of the following must be true:

- Corpus + briefs are auditable
- Source rights are recorded for every item
- Generated code passed isolated sandbox validation
- Splits are frozen and leakage-checked
- Training config is reproducible (fixed seed, pinned versions)
- Adapter is versioned and checksummed
- Domain eval improves over **both** base and retrieval-only baselines
- Regression checks pass
- ≥1 approved runtime loads the adapter reliably
- Serving architecture explicitly states whether inference is Elixir-native or delegated

---

## Intentionally deferred

Pure-Elixir quantized multi-adapter serving; automatic adapter merging; fully autonomous web research without review gates; training on unresolved forum/issue content; security release without dedicated safety evaluation; continual fine-tuning on live conversations; multi-user personal adapters; automatic promotion of newly trained adapters.
