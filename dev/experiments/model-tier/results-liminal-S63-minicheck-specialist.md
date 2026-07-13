# Validation precision: the purpose-built specialist (liminal S63, stacks #109)

The prior three levers (no-think MoE, thinking, dense 32B) and the harness lever (atomic
decomposition) all missed the gate. The open recommendation was: stop testing general LLMs,
test a **fact-check specialist** — a model trained for grounded claim verification, which tops
the LLM-AggreFact leaderboard and is small. This is that test. It is **refuted on both axes.**

## Setup

- **Model:** `bespoke-minicheck:latest` — Bespoke-MiniCheck-7B (internlm2, 7.7B, 32k ctx), the
  model that tops LLM-AggreFact. On the ollama registry, so it runs in the same `/api/chat`
  harness as everything else — no HF-transformers plumbing.
- **Interface:** single call per claim, `Document: {section}\n\nClaim: {claim}` (MiniCheck's
  trained format), built-in system prompt asks for Yes/No. "Yes" = SUPPORTED, "No" = the flag.
  No decompose, no two-stage, no exemplars — the specialist replaces all the scaffolding the
  general MoE needed.
- **Set:** same 691-claim scored set (67 overstatements to catch, 624 CLEAN not to false-flag),
  same PRIORITY front-load. 13 rows dropped as ERROR (unparseable prose drift, see caveat).
- **Gate:** recall ≥ 0.90 AND precision ≥ 0.50 → local solo-viable.

## Result

| Metric | MiniCheck | atomic (MoE + decompose) | best prior single |
|--------|-----------|--------------------------|-------------------|
| **Recall** (overstatements caught) | **0.687** (46/67) | 0.697 (46/66) | 0.697 |
| **Precision** (CLEAN not false-flagged) | **0.168** (tp46 / fp227) | ~0.35 (partial*) | 0.51 (thinking) |
| Speed | 0.3–0.8 s/claim | 6.4 s/claim | — |

*atomic precision is partial (219 CLEAN scored) — its run was preempted to free the GPU for
this probe; recall was already locked.

**Recall ties the general model to within one claim.** A 7B trained *for exactly this task*
lands on the same ~0.69 wall as a general MoE forced through decompose-and-check. Two
completely different attacks, same ceiling. That convergence is the headline: the wall is in
the **data**, not the model or the harness. ~21 of 67 overstatements are gist-preserving
errors ("a 15+ point gap confirms X" — the gap is real, "confirms" is the overclaim) that a
purpose-built checker reads as consistent, same as everything else.

**Precision is the worst of any contender.** MiniCheck flags 227 of 607 CLEAN claims (37%) as
unsupported. This is not a parsing artifact — 215 of those 227 are a clean "No" from the model,
only 12 are prose-parse noise. The specialist is trigger-happy: it holds claims to strict
verbatim substantiation and rejects faithful synthesis that infers across the section. That
also kills it as a cheap prefilter — a "MiniCheck-flags, cloud-confirms" hybrid would ship 5
false alarms for every real catch, and still miss 31% of real errors.

## The one genuinely useful finding: complementary blind spots

MiniCheck and atomic miss the same *count* (~21) but not the same *claims*:

| | count |
|---|---|
| missed by **both** (irreducible core) | 15 |
| caught by atomic only | 5 |
| caught by MiniCheck only | 6 |
| **ensemble (flag if either flags): recall** | **0.773** |

OR-ing a specialist checker and a decompose harness lifts recall from ~0.69 to 0.773 — a real
gain from non-overlapping failure modes. It still misses the 15-claim irreducible core, and
the ensemble's precision is worse (union of false positives, ~0.32 on the shared CLEAN). So it
is a better *safety net*, not a clean gate.

## Verdict

No local lever or combination clears P≥0.50 ∧ R≥0.90 on this set — now including the
purpose-built specialist. Summary of the whole search:

- **Recall ceiling ~0.69, substrate-independent.** General-MoE-with-structure = specialist-checker.
  The 15-claim gist-preserving core defeats every approach. Ensemble lifts to 0.773.
- **Precision:** specialist worst (0.168), thinking general best single (0.51) but its recall
  is only 0.591. The two axes trade against each other and neither point clears the gate.
- **The specialist was the strongest remaining bet and it did not break the wall.** This closes
  the "go smaller and purpose-built" direction the same way "go bigger" (dense 32B) was closed.

The honest hybrid remains: **local flags, cloud confirms** — but local is a leaky net (best
ensemble recall 0.773 misses ~23% of real errors), so the cloud pass cannot be a spot-check of
local's flags; it has to be a full independent pass. Validation stays cloud-owned.

## Method caveats

- **One-word constraint crashes recall.** Forcing MiniCheck to a single token
  ("Answer Yes or No only", num_predict low) biases it hard toward "Yes" and dropped recall
  0.687 → 0.358. It needs to generate freely. All numbers above use the free-generation format.
- **Prose drift.** On ~9% of claims (long benchmark-heavy docs) MiniCheck drifts into
  chain-of-thought instead of Yes/No; parsed by negation-scan, ~2% (13 rows) left unparseable
  and excluded. Concentrated in CLEAN claims, so it does not touch the recall number.
- **Whole-section, not chunked.** MiniCheck's designed protocol chunks long docs and marks
  supported if any chunk supports; this test fed the full ~2500-word section. Chunking would
  likely raise precision (more SUPPORTED verdicts) at the cost of recall — the already-binding
  constraint — so it would not clear the gate. Not re-run for that reason.
