# Stacks article-synthesis benchmark (for local-model tier eval — issue #109)

From: stacks session (S22). For: liminal, to score gemma4-31b / qwen3-30b-a3b / gpt-oss-20b (or others) against the accuracy bar the stacks pipeline needs on the **article-synthesis** stage (agent `article-synthesizer`, currently pinned `model: sonnet`).

This is the reader-facing stage: it turns a merged concept block (claims + per-source tiers) into the `articles/{slug}.md` a practitioner reads and `/stacks:lookup` cites. Its errors are **not** structural like extraction's slug over-proliferation — a downstream validator catches a *contradiction* against a source but does NOT catch a plausible sentence the writer **amplified beyond its claim** (added a mechanism, a number, a "because", or a generalization the claim never stated). That amplification is the synthesis analog of extraction's over-mint, and it is the axis a cheaper tier is most likely to fail: a weak model writes confident, well-formed prose that overstates a thin claim, and the citation stamped on it ships to lookup as fact.

## The task the model must do

Given ONE concept block (a slug, its merged claims, each source's tier) — and, for an update, the existing article — write `articles/{slug}.md`: a frontmatter header plus a body that **reports only what the claims state**, one inline `[source-slug]` citation per claim, higher-tier source winning any conflict. Two judgments separate the tiers:

- **Faithfulness (no over-claim).** Never make a sentence stronger than the claim it rests on. Do not add a mechanism, rationale, number, or generalization ("consistently", "the primary", "outperforms", "teams should") the claim text does not contain.
- **Restraint (refuse the thin concept).** If the merged claims are too thin to support a substantive article (roughly under ~150 words of grounded content), do NOT write — report the shortfall. A weak model pads a thin concept into a fabricated article.

### Prompt to feed your model (verbatim, per item)

```
You are a knowledge writer for a wiki. You receive ONE concept block (a slug, its
merged claims, and each source's tier) and write the article articles/{slug}.md.

Report ONLY what the claims state. Never make a sentence stronger than the claim it
rests on: do not add a mechanism, a rationale ("because…"), a number, or a
generalization ("consistently", "the primary", "outperforms", "teams should") that
the claim text does not contain. Put one inline [source-slug] citation on every claim.
When two claims conflict, the higher-tier source's version wins.

Length follows the grounded claims — write what they support and STOP; do not pad
toward any word count. If the merged claims are too thin for a substantive article
(roughly under ~150 words of grounded content), do NOT write the article — instead
report: "Concept {slug}: insufficient claims — article not written."

OUTPUT (when you write): the article file, starting with YAML frontmatter:
  ---
  last_verified: ""
  sources:            # bare paths, one per source, NO tier suffix
    - sources/{publisher}/{file}.md
  title: {human-readable title}
  routing: {one plain-text line, an asker's words, what it covers + questions answered}
  tags: [{from the allowed list below}]
  ---
  {body — inline [source-slug] citation on every claim, no [VERIFIED]/[DRIFT] marks}
```

### Tag vocabulary (paste as the allowed_tags list — the llm stack's)

```
llm, llmops, evals, llm-as-judge, rag, agents, hallucination, observability,
shadow-mode, context-engineering, prompt-engineering, guardrails, memory, mcp,
multi-agent, cost-economics, fine-tuning
```

## Test items (concept block is inline and IS the scoring key; source path is provenance only, not a scoring input)

Each item gives the **concept block** — the model's input AND the scoring ground truth. Recall and over-claim are scored **against the block's claims**, not against any external article: the synthesizer writes *from the block* (it never reads the raw source), so the block alone defines both what must appear (every claim) and the ceiling (nothing beyond it). The published `articles/{slug}.md` of the same name is a **prose-shape reference only** — it was written from the fuller parent source and then audit-validated, so it legitimately contains claims the block does not and carries a non-empty `last_verified`; do NOT score against it. The source path is listed for provenance, not as a scoring input (source-fidelity is the extraction stage's concern, not synthesis).

---

### Item 1 — faithful single-concept (source: `.../llm/sources/arxiv/arxiv-2507.13334-context-engineering-survey.md`, tier 2)

Clean single-source write. Recall every claim, add nothing. Feed this block:

```
## Concept: LLM Evaluation Frameworks

slug: llm-evaluation-frameworks
title: LLM Evaluation Frameworks
source_paths:
  - sources/arxiv/arxiv-2507.13334-context-engineering-survey.md (tier 2)
target_article: ""

### Claims

- Evaluation operates at two levels: component-level (retrieval quality, prompt
  effectiveness, compression efficiency — measured in isolation so failures localize)
  and system-level (end-to-end task performance and resource efficiency — measured on
  the integrated pipeline to catch interaction effects). [source: arxiv-2507.13334-context-engineering-survey]
- Foundational component benchmarks cover retrieval, prompt effectiveness, long-context
  understanding, and multimodal integration. [source: arxiv-2507.13334-context-engineering-survey]
- System implementation benchmarks cover RAG pipeline quality, agent task performance,
  multi-agent coordination, and tool-use effectiveness. [source: arxiv-2507.13334-context-engineering-survey]
- Recurring pitfalls: a benchmark-vs-real-world gap; memory-system isolation (metrics
  don't transfer across subsystem boundaries); O(n^2) scaling limits on pairwise or
  full-context-reread approaches; transactional-integrity failures (state bleed between
  test cases); self-validation dependency (model grading its own outputs without a
  ground-truth anchor); context-handling failures that only surface in long-horizon tasks.
  [source: arxiv-2507.13334-context-engineering-survey]
- Safety and robustness assessment is a distinct target needing purpose-built cases, not
  repurposed accuracy benchmarks: adversarial robustness (prompt injection, jailbreaks),
  hallucination detection, attribution/grounding verification, and agent-behavior safety.
  [source: arxiv-2507.13334-context-engineering-survey]
- Emerging paradigms move beyond static benchmark accuracy toward interactive evaluation
  environments, long-horizon task assessment, and resource-efficiency measurement (tokens,
  latency, cost per correct answer). [source: arxiv-2507.13334-context-engineering-survey]
```

**Gold** = an article that states all 6 block claims and nothing beyond them, `last_verified: ""`, `tags` a subset of `{llm, llmops, evals, llm-as-judge, rag, agents, hallucination, observability}`, one source (no tier-conflict). Recall target **6/6**; **over-claims expected: 0** — any sentence asserting beyond the 6 claims counts. (The published `llm-evaluation-frameworks.md` is a prose-shape reference, not the scoring key — it carries content from the full survey the block omits.)

---

### Item 2 (cliff) — over-claim trap, multi-source (sources: `zenml-2025-12-llmops-1200-deployments`, tier 3; `evidentlyai-llm-as-a-judge-guide`, tier 3)

The tier-separating item. Every claim is a **named-company practice** with a qualifier. A weak tier universalizes it ("teams should…"), drops the qualifier, or bolts on a mechanism/guarantee the source never states. Each amplification is one over-claim. Feed this block:

```
## Concept: Production Eval Systems

slug: production-eval-systems
title: Production Eval Systems: Regression Datasets, LLM-as-Judge, Shadow Mode, Red Teaming
source_paths:
  - sources/zenml/zenml-2025-12-llmops-1200-deployments.md (tier 3)
  - sources/evidentlyai/evidentlyai-llm-as-a-judge-guide.md (tier 3)
target_article: ""

### Claims

- Golden datasets are curated inputs with human-reviewed expected outputs; the failure
  cases that seed them come from production incidents, not synthetic generation.
  [source: zenml-2025-12-llmops-1200-deployments]
- Ramp converts each user-reported failure into a regression test case, but the raw
  report is reviewed and canonicalized under human oversight first — used directly it
  introduces affinity bias (users report the failures that affect them). [source: zenml-2025-12-llmops-1200-deployments]
- Shadow mode runs the new system alongside production on the same input; only the
  current system's output is served, the shadow output is logged and compared after the
  fact. [source: zenml-2025-12-llmops-1200-deployments]
- Ramp enables live execution of a shadow agent only once shadow accuracy reaches a
  defined threshold over a validation window — the threshold makes the gate auditable
  rather than a deploy-time judgment call. [source: zenml-2025-12-llmops-1200-deployments]
- LLM-as-judge uses a separate model to score outputs; routing generation and evaluation
  to different providers is a documented practice that prevents a model grading its own
  test. [source: zenml-2025-12-llmops-1200-deployments]
- An LLM judge fills the gap where pass/fail metrics don't capture quality — tone,
  completeness, factual framing — at volumes human review can't match. [source: evidentlyai-llm-as-a-judge-guide]
- Red teaming is adversarial testing meant to break the system, and production teams run
  it continuously throughout the lifecycle, not as a one-time pre-launch gate. [source: zenml-2025-12-llmops-1200-deployments]
```

**Gold** = an article that states all 7 block claims with their qualifiers intact — each company-attributed practice kept attributed, each hedge preserved — `last_verified: ""`, **over-claims 0.** (The published `production-eval-systems.md` is a prose-shape reference only; scoring is block-relative.) The specific amplification traps a judge must flag if they appear:

| Trap | Faithful (gold) | Over-claim (fail) |
|---|---|---|
| Ramp's failure→test practice | "Ramp converts…" (attributed, with human curation) | "Teams should convert every failure into a test" (universalized, curation dropped) |
| Shadow-mode threshold | "live execution once shadow accuracy reaches a defined threshold" | "shadow mode guarantees safe deployment" (added guarantee) |
| Separate-provider judge | "a documented practice that prevents grading its own test" | "you must always use a different provider **because** a model always inflates its own scores" (added mechanism + hardened to a rule) |
| Affinity bias | "user reports skew toward common cases" | "user reports are unreliable" (over-general) or any invented percentage |

Recall floor still applies (≥ 0.90 of the 7 claims present); the discriminating floor is **0 over-claims**.

---

### Item 3 — thin-concept refusal (source: `evidentlyai-llm-as-a-judge-guide`, tier 3)

Restraint check. The block carries a single thin claim — below the substantive-article floor. The correct action is to **refuse**, not to pad. Feed this block:

```
## Concept: Judge Verbosity Monitoring

slug: judge-verbosity-monitoring
title: Monitoring Judge Verbosity Bias
source_paths:
  - sources/evidentlyai/evidentlyai-llm-as-a-judge-guide.md (tier 3)
target_article: ""

### Claims

- Track response length alongside LLM-judge scores to catch verbosity bias, where the
  judge rates longer answers higher without their being better. [source: evidentlyai-llm-as-a-judge-guide]
```

**Gold** = **no article written.** The model reports a shortfall, e.g. "Concept judge-verbosity-monitoring: insufficient claims (1 claim, ~35 words grounded) — article not written." Writing a 300+ word article here is the **over-write failure** (the model fabricated context the single claim does not contain). Note: verbosity-bias monitoring is legitimately covered as one line inside the existing `llm-as-judge` article — this block is not enough to stand as its own article, which is exactly the judgment being tested.

## Metric + the bar we need

Score each item, then aggregate. Faithfulness is **claim-tracing, not a 1-5 preference score** — for each article sentence, ask "does a block claim support this, at this strength?"; a No is an over-claim. Do the tracing with a judge model that **differs from the writer** (self-enhancement bias inflates a model grading its own family) and eyeball-calibrate against the gold.

1. **Grounding recall** = block claims the article states / block claims, scored **per item** (target 6/6 on item 1, 7/7 on item 2 — do not micro-average across items, which would let a 12/13 hide a fully-dropped claim). **Floor ≥ 0.90 per item.**
2. **Over-claim count** = article sentences asserting a mechanism / number / generalization / rationale no block claim supports (item 2's trap table enumerates the ones that matter). **Floor: 0 on items 1 and 2.** This is the precision axis a cheaper tier fails — the synthesis analog of extraction's mint discipline.
3. **Structural validity** — two machine checks plus one judge check (no single script covers the schema): **(a)** key presence — `scripts/assert-structure.sh {file} article-md synthesis-benchmark` (arg order `<path> <type> <label>`; this kind ONLY verifies `title:` and `last_verified:` exist — it does not parse YAML or check `routing`/`sources`/`tags`); **(b)** greps — `sources:` bare (no ` (tier` suffix, no `{stack}/` prefix), zero `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` marks, `routing:` present, at least one `[source-slug]` citation present; **(c)** judge check (grep cannot do this) — every substantive claim carries an inline citation, and every `tags:` value is in the allowed list (`normalize-tags.sh` is a corpus-wide drift check, not a single-file gate, so confirm tags by eye against the list above). **Floor: all pass** (items 1–2).
4. **Restraint** = item 3 correctly refused (no article written, shortfall reported). **Floor: correct refusal** (binary).
5. **Determinism** (report, not gated) = byte-identical body across 3 greedy passes. A deterministic writer is a real pipeline win over both Claude tiers.

A model that clears floors 1–4 is a viable synthesis tier. The likely failure signature for a weak tier is: recall fine, structure fine, but **over-claims > 0 on item 2** and/or **writes an article on item 3** — i.e. it is fluent but not restrained. If a local model clears all four deterministically, it is a strict upgrade on this stage: ~$0 marginal, reproducible, and the restraint the discrimination half needs.

## What to send back

Per model: grounding recall, over-claim count (with the offending sentences quoted, per item), structural pass/fail, the item-3 refusal verdict, and the determinism result. Include the raw article bodies for items 1–2 so we can eyeball the divergences. If a model clears the bar, note its tok/s so we can weigh throughput against the cloud tiers. Extraction settled first (`extraction-benchmark.md`); synthesis is the second stage — validator (a shadow test against sonnet's catch-rate) and enrichment follow.
