# Future investigation: substrate candidates + how to screen them (liminal S63, stacks #109)

> **UPDATE (tested):** the top recommendation below — a fact-check specialist (MiniCheck) —
> was run. It is **refuted on both axes**: recall 0.687 (ties the general model's wall),
> precision 0.168 (worst of any contender). See `results-liminal-S63-minicheck-specialist.md`.
> The screening reframe still stands as *theory*, but the strongest bet it produced did not
> beat the general approaches on our set. The ~0.69 recall wall is substrate-independent.

Companion to the S63 validation-precision results. If the atomic-decomposition harness
lever (harness-owns-structure, ADR-002) is the winning design, the open question is
*which local model runs it best*. This note captures the candidates and — more usefully —
**how to screen models for this need**, because the benchmarks a general model advertises
are the wrong signal.

## The screening insight (the load-bearing part)

Our task is **grounded claim verification**: given a claim and its cited passage, does the
passage support the claim, down to the number, the named entity, the hedge. The residual
failure (recall plateaus ~0.70 even on the atomic harness) is **gist-preserving errors** —
"Qwen3-8B" read as entailed by "an 8B model", "15+ point gap" waved past "27pp / 31pp".

The benchmarks models advertise — **GPQA, MMLU-Pro, GSM8K** — are the WRONG signal, arguably
anti-correlated: they reward knowledge and fluent reasoning, which IS the gist-reading that
fails us. A model that scores 85 on MMLU-Pro tells us nothing about whether it will notice a
swapped number. **Screen on grounded-fact-checking and contrastive/adversarial NLI instead:**

| Benchmark | Why it predicts OUR need |
|-----------|--------------------------|
| **LLM-AggreFact** (the MiniCheck leaderboard) | The most direct match: claim + document -> supported/not, ranked. Small specialized checkers beat giant general LLMs here — the key reframe. **Look here first.** |
| **VitaminC** | Contrastive NLI trained on Wikipedia edits where ONE fact changed. Purpose-built to be sensitive to exactly our failure (small factual swaps). A high-VitaminC model is one that does NOT gist-gloss. |
| **ANLI** (adversarial NLI) | Adversarially-collected entailment — the hard, gist-preserving cases, not surface lexical overlap. |
| **RAGTruth / HaluBench / RAGAS-faithfulness** | Hallucination detection in grounded/RAG settings — the production shape of our task. |

**The reframe this implies:** we have been testing general instruct/reasoning models (qwen3-30b-a3b,
qwen3-32b, thinking variants). The models that top LLM-AggreFact are often **purpose-built
fact-checkers / NLI-tuned models** (e.g. the MiniCheck line, DeBERTa-NLI-based checkers), which
are small AND beat big general LLMs on this exact task. The best substrate may not be a bigger
general LLM at all — it may be a small NLI/fact-check specialist. That is a different and
cheaper search than "go bigger", and it targets the gist-equivalent residual head-on.

## Model candidates (general-LLM lane)

- **Qwen3.6-27B (straight)** — TOP general-LLM candidate. Newer generation than the qwen3-30b-a3b/
  qwen3-32b tested; thinking intact (unlike ThinkingCap below). The high-value test is
  **Qwen3.6-27B on the atomic harness** — newer reader x best framing — aimed directly at the
  gist-equivalent residual atomic alone can't fix. Only worth it if a newer general model reads
  less gist-y; screen it on VitaminC/ANLI first before spending a full gate run.
- **ThinkingCap-Qwen3.6-27B** (bottlecapai) — a thinking-token-*reduction* finetune (~46% fewer
  reasoning tokens). Pointed the WRONG way for the recall lever (our gain came from MORE
  span-by-span thinking, not less). NOT a faithfulness model. Its efficiency only helps if the
  answer is high-volume atomic batching, where cheap per-atom calls matter — a throughput
  substrate, not a capability one. Lower priority than straight Qwen3.6.

## Sequencing

1. ~~Finish the atomic run~~ — done: recall plateaus 0.697, misses the 0.90 gate.
2. ~~If it misses, test a fact-check/NLI specialist (MiniCheck-class)~~ — **done and refuted.**
   MiniCheck recall 0.687 (ties the wall), precision 0.168 (worst). The gist-equivalent residual
   defeats the specialist too; it also over-flags too hard to serve as a prefilter.
3. **What's actually left, if anyone reopens this:**
   - The 15-claim irreducible core is the only real target — the claims *both* the specialist
     and the harness miss. Manual read of those 15 to see if they are truly gist-preserving
     (unfixable at 7B) or share a structure a targeted check could catch (e.g. quantifier /
     certainty-word overstatement, which a rule could flag before any model runs).
   - The complementary-blind-spot finding (ensemble recall 0.773) says diversity helps more than
     capability. A cheap deterministic pre-check for over-claim words ("confirms", "guarantees",
     "always") OR'd with one model might beat any single model — worth a look before more models.
   - VitaminC/ANLI screening is still the right lens for a *new* specialist, but MiniCheck was
     the strongest one available and it did not clear, so this is low-priority.
