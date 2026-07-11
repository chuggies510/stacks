# Model-tier & context-efficiency test area

Tracked by **#109** (epic); extraction instance is **#95**.

Purpose: for each stacks agent stage, find the cheapest model — a cloud tier OR a
local LLM — that holds the stage's accuracy floor, and the **prompt/context
improvement** that gets it there. The recurring finding is that a stage's model tier
is usually not the accuracy blocker; the input context is.

## Method (per stage)

1. Define the stage's judgment surface — the actual decision the agent makes.
2. Build a gold-set benchmark: a few human-validated items including a tier-separating
   "cliff" item, a metric, and a floor.
3. Find the prompt/context change that lets a cheaper model hold the floor.
4. Score cloud tiers (haiku) and local models (liminal's RTX 3090 rig) against the
   floor, determinism reported.
5. Decide: cheapest tier that holds + the change that got it there.

## Stages

| Stage | Agent | Benchmark | Status |
|---|---|---|---|
| Extraction | source-extractor | `extraction-benchmark.md` | Fix shipped (0.57.0 scoped slugs). Haiku validation in flight; local qwen clears behind a harness. |
| Synthesis | article-synthesizer | `synthesis-benchmark.md` | Benchmark ready (S22) — 3 items, faithfulness/over-claim + refusal floors. Awaiting liminal local scores. |
| Validation | validator | `validation-benchmark.md` | Benchmark ready (S22) — 7-item labeled set, poison-recall + false-correction floors (offline layer; shadow test #95 above it). Awaiting liminal local scores. |
| Enrichment | enrichment | — | not started |

## Key finding (extraction)

Over-minting was information starvation, not a weak tier. A bare 42-slug list makes
models fragment one existing article into several new sub-topic slugs; a `slug — scope`
map (the `index.md` `## Articles` routing lines) drops excess minting to 0 across every
tier (gemma 7-8→0, qwen 0-19→0). Shipped as 0.57.0.

## Files

- `extraction-benchmark.md` — the extraction gold set + metric + floors (self-contained; the spec handed to liminal).
- `synthesis-benchmark.md` — the synthesis gold set: faithfulness (no over-claim) + refusal floors, 3 items (self-contained; the spec handed to liminal).
- `validation-benchmark.md` — the validation gold set: poison-recall (catch overstatement/contradiction) + false-correction (don't over-trim) floors, 7 labeled items across all verdict classes (self-contained; the offline layer, shadow test #95 above it).
- `results-liminal-S59.md` — local-model scores + raw per-item output lines.
