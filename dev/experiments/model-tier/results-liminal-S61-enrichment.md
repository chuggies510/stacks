# Enrichment stage — local-tier grade (liminal S61, stacks #109)

Scores qwen3-30b-a3b-instruct against `enrichment-benchmark.md` (6 items, offline grounding
judgment, temp 0, 3 passes, native `/api/chat`). This closes the **fourth** offline stage —
extraction, synthesis, validation, enrichment now all have a local-tier read.

## Result: clears every GROUNDING floor byte-DET; fails only DUP (as-prompted)

| Metric (floor) | qwen3-30b | Verdict |
|----------------|-----------|---------|
| **false-CANDIDATE rate**, traps {2,3} (floor 0) | **0/2** | **PASS** — refused both on-topic-but-silent passages |
| grounding recall {1,4,6} (≥0.90) | 3/3 | PASS |
| tier accuracy, fixed {1,4,5} (3/3) | 3/3 | PASS |
| **DUP detection**, item 6 (correct) | **CANDIDATE:2** | **FAIL as-prompted** (see below — belongs in the harness) |
| determinism (3 passes) | byte-DET | identical all 3 |

The axis the stage exists to hold — false-CANDIDATE under topical similarity, the #95 accuracy
axis — qwen3-30b holds **clean and byte-DET**. It refused both traps with correct, specific
reasoning:
- Item 2: *"mentions shadow mode and threshold-based activation but does not specify a two-week
  validation window."*
- Item 3: *"mentions position bias and mitigation attempts but does not claim ... that averaging
  across three independent judge models fully eliminates it."*

That is exactly the restraint-under-topical-similarity the benchmark predicted a fluent weak tier
would fail (line 107). It doesn't. Same signature as the validator's per-claim poison recall (1.00)
and the synthesizer's 0 over-claims: **one object-level judgment, in isolation → the weak tier is
good.**

## The one failure is not grounding, not capability — it's dedup, and it belongs in code

Item 6: the passage *does* ground the claim and the tier *is* 2 (both correct); the model returned
`CANDIDATE | tier:2` instead of `DUP`. It failed to notice the candidate URL is already in the
filed-sources listing. DUP is the one sub-task in the whole stage that is **not** a topical judgment
— it is `candidate_url in filed_urls`, a set-membership test.

**Ablation (item 6, 3 passes each, both byte-DET):**

| Prompt variant | Verdict |
|----------------|---------|
| A — grounding-first, dedup as an inline clause ("if URL already filed → DUP") | `CANDIDATE:2` ×3 |
| B — dedup elevated to explicit **STEP 1** (compare URLs FIRST, return DUP and STOP) | `DUP \| arxiv-...` ×3 |

So it is **not a capability gap** — with the URL check made primary and sequential, the model dedups
perfectly and stably. It is an attention-ordering effect: when grounding is the primary framing, the
model resolves on "does this passage ground the claim? yes → CANDIDATE" and skips the trivial URL
comparison even when instructed to perform it. And note it flips **deterministically** (A always
CANDIDATE, B always DUP) — not the non-monotonic prompt-chaos the synth-refusal showed. A stable
ordering effect, not fragility.

## Recommendation: same rule, fourth stage — dedup is a harness gate, not a model call

The prompt fix (variant B) works and is byte-DET. But the robust fix is the one that mirrors the
validator (per-claim isolation) and synth-refusal (claim-count gate) conclusions, and it is even
clearer-cut here because dedup is a pure string containment check:

- Before calling the model, the harness checks `candidate_url` against the filed-sources listing it
  already holds as structured data. Exact match → emit `DUP | <slug>` in code, **skip the model call
  entirely**.
- Only when the URL is new does the model get asked the one thing it's good at: does this passage
  ground this specific claim, and at what tier.

There is zero reason for a probabilistic model to perform a set-membership test the harness can do in
one line with 100% reliability. Handing it to the model is what produced the only floor failure.

## Net across all four stages

| Stage | Local object-level judgment | The decision to pull OUT of the model |
|-------|-----------------------------|----------------------------------------|
| Extraction | transcription (green at larger tier; 4B-LoRA red) | — |
| Synthesis | synth the block (13/13 claims, 0 over-claims) | refuse-or-write → **claim-count gate** |
| Validation | verify one claim (poison recall 1.00) | clean-or-flag whole-article batch → **per-claim isolation** |
| Enrichment | ground one claim (false-CAND 0, tier 3/3, byte-DET) | dedup (`url in filed`) → **containment gate** |

The through-line, now confirmed on all four worker stages: **give the weak local tier exactly one
object-level judgment per call, and move every mechanical or meta decision around it — refuse, batch-
scan, dedup — into the harness.** Enrichment is the sharpest case: the grounding discrimination is
genuinely good (byte-DET clean on the exact traps designed to break it), and the sole failure was a
decision the model should never have been handed.

**Viability:** qwen3-30b is a viable enrichment **grounding** tier — clears every discrimination floor
byte-DET — with dedup handled as a deterministic harness gate (where it belongs at any tier). The raw
scorer reads "NOT viable" only because DUP is a gated floor and the model failed it *as-prompted*;
that floor is a harness responsibility, not a grounding-quality signal.
