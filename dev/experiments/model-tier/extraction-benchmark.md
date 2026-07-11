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
agent-harness-engineering, agent-memory-systems, compiled-ai-pattern,
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
mcp-production-patterns, multi-agent-orchestration, orpo-hard-negatives, production-eval-systems,
prompt-distillation-few-shot-compression, prompt-engineering, rag-chunking-strategy-selection,
retrieval-augmented-generation, self-correction-loops, token-budget-management,
tool-integrated-reasoning
```

## Test items (source text is on this machine — read the path)

| # | Source path | Kind |
|---|---|---|
| 1 | `/home/chris/chungus/dev/library-stack/llm/sources/arxiv/arxiv-2306.05685-llm-as-judge-mt-bench.md` | single-concept, clear reuse |
| 2 | `/home/chris/chungus/dev/library-stack/llm/sources/tianpan/tianpan-token-budget-production.md` | single-concept, clear reuse |
| 3 | `/home/chris/chungus/dev/library-stack/llm/sources/zenml/zenml-2025-12-llmops-1200-deployments.md` | **cliff** — rich multi-concept, over-mint trap |

## Gold answers (human-validated against the existing articles, S21)

**Item 1** — exactly 1 concept:
```
llm-as-judge | reuse:llm-as-judge | tier:2
```
New slugs expected: **0**.

**Item 2** — exactly 1 concept (either reuse target accepted; both articles exist):
```
llm-cost-control-production | reuse:llm-cost-control-production | tier:3
   (accept also reuse:token-budget-management)
```
New slugs expected: **0**.

**Item 3 (cliff)** — these 10 existing-article concepts must be recalled, all tier 3:
```
context-engineering-production        | reuse | tier:3
guardrails-infrastructure             | reuse | tier:3
mcp-production-patterns                | reuse | tier:3
durable-execution-agent-orchestration | reuse | tier:3
agent-harness-engineering             | reuse | tier:3
production-eval-systems                | reuse | tier:3
llm-cost-control-production            | reuse | tier:3
agent-memory-systems                   | reuse | tier:3
multi-agent-orchestration              | reuse | tier:3
retrieval-augmented-generation         | reuse | tier:3
```
Mint allowance: **≤1** new slug is acceptable here (`agent-rl-fine-tuning` — OpenPipe GRPO / Cursor online-RL — is a defensible real gap). Minting ≥2 new slugs is the **over-mint failure** (haiku minted 3, two of which were thematic fragments of subsystems it had already emitted as reuse blocks).

## Metric + the bar we need

Score each item, then aggregate:

1. **Reuse recall** = (gold existing-slug concepts the model emitted with the correct existing slug) / (gold existing-slug concepts). **Floor ≥ 0.90.**
2. **Mint discipline** = new slugs minted beyond the allowance (0 on items 1–2, ≤1 on item 3). **Floor: 0 excess on 1–2, ≤1 on 3.** This is the precision axis your podly numbers predict gemma wins.
3. **Tier accuracy** = fraction of matched concepts with the exact gold tier. **Floor ≥ 0.90.**
4. **Determinism** (report, not gated) = byte-identical slug set across 3 greedy passes. A deterministic stage is a real pipeline win over both Claude tiers.

A model that clears floors 1–3 is a viable extraction tier. If gemma4-31b clears them deterministically, it's a strict upgrade on this stage: ~$0 marginal, reproducible, and higher restraint than haiku.

## What to send back

Per model: the three metric numbers (reuse recall, mint discipline, tier accuracy), the determinism result, and the raw per-item output lines so we can eyeball the divergences. If a model clears the bar, note its tok/s so we can weigh throughput vs the cloud tiers. This benchmark extends later to the `validator` stage (a shadow test), but extraction is the one to settle first.
