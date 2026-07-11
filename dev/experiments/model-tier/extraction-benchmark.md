# Stacks source-extraction benchmark (for local-model tier eval — issue #95)

From: stacks session (S21). For: liminal, to score gemma4-31b / qwen3-30b-a3b / gpt-oss-20b (or others) against the accuracy bar the stacks pipeline needs on the **source-extraction** stage.

This is the highest-value stage to downgrade (largest token consumer; a strong downstream validator does NOT catch its errors, because they are structural — slug over-proliferation — not claim-overstatements). Cloud A/B (S21) found: **haiku ties sonnet on the transcription half but over-mints slugs on rich multi-concept sources** (the discrimination half). Your podly precision numbers (gemma4-31b 0.986/0.999) suggest gemma is exactly the restraint profile that half needs — this benchmark confirms it on THIS task.

## The task the model must do

Read ONE source's text and emit its concepts as concept blocks. For each **distinct, in-scope** concept:
- assign a kebab-case slug;
- if an EXISTING article already covers it, **reuse that slug** (do not rename, do not mint a variant); only mint a NEW slug when no existing article covers the concept;
- assign a source **tier** (1–4) per the rubric below;
- be **conservative**: don't fragment one concept into several, don't mint a slug for a concept an existing article already covers, don't invent concepts the source doesn't discuss, and discard pure reference material (flag/endpoint/config listings with no behavior knowledge).

### Prompt to feed your model (verbatim, per source)

```
You extract knowledge from ONE source into concept entries for a knowledge wiki.
INPUTS: (a) the source text; (b) EXISTING_SLUGS — the articles that already exist;
(c) the tier rubric.
For each DISTINCT, in-scope concept the source covers (in-scope = LLM production/
research knowledge; discard pure reference such as CLI-flag or API listings):
  - assign a kebab-case slug;
  - if an existing article in EXISTING_SLUGS covers this concept, REUSE that exact
    slug; only mint a NEW slug when none covers it;
  - assign tier 1-4 per the rubric.
Be CONSERVATIVE: do not fragment one concept into several, do not mint a slug for a
concept an existing article already covers, do not invent concepts.
OUTPUT: one line per concept, exactly:  <slug> | reuse:<existing-slug|NEW> | tier:<N>
Nothing else.
```

### Tier rubric (paste into the prompt as the rubric)

```
Tier 1 Official     — vendor docs, model cards, API reference, official cookbooks
Tier 2 Standard     — peer-reviewed papers, vendor research blogs, established surveys
Tier 3 Practitioner — LLMOps practitioner blogs, conference talks, production case studies
Tier 4 General      — forum posts, X/HN/Reddit threads
Higher tiers win conflicts.
```

### EXISTING_SLUGS (paste into the prompt — the llm stack's current articles)

```
agent-harness-engineering, agent-memory-systems, apple-silicon-unified-memory-llm-serving, compiled-ai-pattern,
constrained-decoding-structured-output, context-engineering, context-engineering-production,
context-window-management, dnip-calibration, dora-weight-decomposed-lora,
durable-execution-agent-orchestration, focal-loss-class-weighted-token-loss,
generator-verifier-gap, guardrails-infrastructure, llm-as-judge, llm-cost-control-production,
llm-evaluation-frameworks, llm-hallucinated-citations, llm-judge-gate-wiring,
llm-output-stylistic-tells, llm-output-validation-pipeline,
lora-base-model-recall-precision-alignment, lora-degenerate-output-diagnosis,
lora-eos-pad-collision, lora-fast-eval-iteration-gate, lora-hybrid-mamba-architecture-screening,
lora-merge-then-quantize-vs-quant-aware, lora-output-schema-coupling, lora-prompt-loss-weight,
lora-prompt-mismatch, lora-rank-classification, lora-target-modules-attn-vs-mlp,
mcp-production-patterns, moe-cpu-ram-expert-offload, moe-total-memory-sizing, multi-agent-orchestration, orpo-hard-negatives, production-eval-systems,
prompt-distillation-few-shot-compression, prompt-engineering, rag-chunking-strategy-selection,
retrieval-augmented-generation, self-correction-loops, token-budget-management,
tool-integrated-reasoning
```

> Reproducibility: this list is a point-in-time snapshot and drifts as the stack grows (three articles were added after S21). To re-run faithfully, regenerate `EXISTING_SLUGS` from `library-stack/llm/articles/*.md` at run time, or pin it to a specific library-stack commit.

## Test items (source text is on this machine — read the path)

| # | Source path | Kind |
|---|---|---|
| 1 | `/home/chris/chungus/dev/library-stack/llm/sources/arxiv/arxiv-2306.05685-llm-as-judge-mt-bench.md` | single-concept, clear reuse |
| 2 | `/home/chris/chungus/dev/library-stack/llm/sources/tianpan/tianpan-token-budget-production.md` | two concepts, clear reuse (no fragment) |
| 3 | `/home/chris/chungus/dev/library-stack/llm/sources/zenml/zenml-2025-12-llmops-1200-deployments.md` | **cliff** — rich multi-concept, over-mint trap |

## Gold answers (human-validated against the existing articles, S21)

**Item 1** — exactly 1 concept:
```
llm-as-judge | reuse:llm-as-judge | tier:2
```
New slugs expected: **0**.

**Item 2** — exactly 2 concepts (both already have articles; the source covers upstream component budgeting AND gateway/monitoring cost control):
```
context-engineering        | reuse:context-engineering        | tier:3
llm-cost-control-production | reuse:llm-cost-control-production | tier:3
```
New slugs expected: **0**. `token-budget-management` is NOT an accepted target — it covers tokenization/capacity estimation only (its cited source is the OpenAI tokenization page), not the Tianpan production budgeting claims. Emitting only one of the two concepts is a recall miss; minting a `token-budget` fragment is an over-mint.

**Item 3 (cliff)** — these 10 existing-article concepts must be recalled, all tier 3 (full output schema, matching the prompt's `<slug> | reuse:<existing-slug|NEW> | tier:<N>`):
```
context-engineering-production        | reuse:context-engineering-production        | tier:3
guardrails-infrastructure             | reuse:guardrails-infrastructure             | tier:3
mcp-production-patterns                | reuse:mcp-production-patterns                | tier:3
durable-execution-agent-orchestration | reuse:durable-execution-agent-orchestration | tier:3
agent-harness-engineering             | reuse:agent-harness-engineering             | tier:3
production-eval-systems                | reuse:production-eval-systems                | tier:3
llm-cost-control-production            | reuse:llm-cost-control-production            | tier:3
agent-memory-systems                   | reuse:agent-memory-systems                   | tier:3
multi-agent-orchestration              | reuse:multi-agent-orchestration              | tier:3
retrieval-augmented-generation         | reuse:retrieval-augmented-generation         | tier:3
```
Mint allowance: **0**. The OpenPipe-GRPO / online-RL concept is NOT a new gap — `agent-harness-engineering` already covers it (its body states the OpenPipe ART-E GRPO result verbatim), so a mint like `agent-rl-fine-tuning` is a fragment of a concept already required as reuse above. Minting ANY new slug here is the **over-mint failure** (haiku minted 3, all fragments of subsystems it had already emitted as reuse blocks).

## Metric + the bar we need

Score **per item** — do NOT micro-average across items, or a total-count near-miss hides a fully-failed item (13 gold concepts = 1 + 2 + 10; 12/13 = 0.92 would "pass" while dropping item 1 or 2 entirely). Gold concept counts: item 1 = 1, item 2 = 2, item 3 = 10.

1. **Reuse recall** (per item) = correct existing-slug concepts emitted / gold concepts. **Floor: item 1 = 1/1, item 2 = 2/2, item 3 ≥ 9/10 (0.90).**
2. **Reuse precision** (per item) = of the reuse slugs the model emitted, the fraction that match a gold concept. **Floor: 0 false reuse.** This closes the emit-everything hole: a model that dumps every EXISTING_SLUG scores perfect recall but fails precision here — a reuse slug for a concept the source does not cover is as wrong as a miss.
3. **Mint discipline** = new (`NEW`) slugs emitted. Allowance is **0 on every item** (each test source's concepts are all already covered). **Floor: 0 mints, all items.** This is the precision axis your podly numbers predict gemma wins.
4. **Tier accuracy** = fraction of correctly-matched concepts with the exact gold tier. **Floor ≥ 0.90.**
5. **Determinism** (report, not gated) = byte-identical slug set across 3 greedy passes. A deterministic stage is a real pipeline win over both Claude tiers.

A model that clears floors 1–4 is a viable extraction tier. If gemma4-31b clears them deterministically, it's a strict upgrade on this stage: ~$0 marginal, reproducible, and higher restraint than haiku.

## What to send back

Per model: the per-item metric numbers (reuse recall, reuse precision, mint discipline, tier accuracy), the determinism result, and the raw per-item output lines so we can eyeball the divergences. If a model clears the bar, note its tok/s so we can weigh throughput vs the cloud tiers. This benchmark extends later to the `validator` stage (a shadow test), but extraction is the one to settle first.
