# Synthesis-benchmark results — local models (liminal S61, for stacks #109)

Harness: local ollama on the 3900x (RTX 3090), native `/api/chat`, greedy (`temperature 0`),
`num_ctx=16384`, 3 passes per item. Block-relative scoring (recall + over-claim vs the concept
block's own claims, NOT the published article — per the benchmark's scoring frame). Raw bodies:
`scratchpad/synth_run/<model>__item<N>__pass<P>.md` on the 3900x (transient); reproduce via
`scratchpad/synth_run/run_synth.py`.

## Verdict: qwen3-30b-a3b is a clean pass and the pick. It is the ONLY model that clears every floor byte-deterministically, and it is 5-9x faster than the other two.

It is also the same model that already clears extraction (with the described-slug harness) and
validation (S59). One local model, three of four stages.

## Scorecard

| Model | Recall i1 / i2 | Over-claims | Item-3 refusal | Determinism | Tags | tok/s |
|---|---|---|---|---|---|---|
| **qwen3-30b-a3b-instruct** | 6/6, 7/7 | **0** | ✓ correct | **byte-DET (all 3 items)** | 1 out-of-vocab/article ✗ | **~195** |
| gemma4-31b-it-qat | 6/6, 7/7 | **0** | ✓ correct | item1 **NONDET**, i2/i3 DET | clean ✓ | ~35 |
| qwen3.6-27b | 6/6, 7/7 | **1** (de-attribution) | ✓ correct | byte-DET (all 3 items) | clean ✓ | ~21-38 (degrading) |

Recall floor (>=0.90/item) and refusal floor: **all three pass.** The tiers separate on the
over-claim axis, determinism, and speed.

## Over-claim detail (offending sentences quoted)

- **qwen3-30b-a3b: 0.** Kept every company attribution and hedge on item 2. Did NOT universalize
  ("teams should"), did NOT add "shadow mode guarantees safe deployment", did NOT harden the
  separate-provider judge into a because-rule. Clean.
- **gemma4-31b: 0.** Same — attributions and hedges intact ("Ramp converts…", "provided the raw
  reports are first reviewed…", "makes the gate auditable…", "documented practice to prevent…").
- **qwen3.6-27b: 1.** Dropped the Ramp attribution on claim 2 — wrote
  *"User-reported failures are converted into regression test cases only after human review and
  canonicalization"* where the claim is *"Ramp converts each user-reported failure…"*. It kept the
  human-curation qualifier (so not a full universalization), but the named-company practice was
  de-attributed to a general one. This is the trap table's row-1 amplification in mild form.

## Structural

- **qwen3-30b-a3b:** frontmatter valid, `sources:` bare, `routing:` present, per-claim citations,
  no VERIFIED/DRIFT marks — **one fault:** invents an out-of-vocab tag per article (`safety` on
  item 1, `red-teaming` on item 2; neither in the allowed list). Mechanically fixable: post-filter
  tags to the vocab, or harden the prompt. Not a reasoning/capability gap.
- **gemma4-31b / qwen3.6-27b:** tags all in-vocab; structure otherwise equivalent.

## Determinism (the pipeline win)

- **qwen3-30b-a3b:** byte-identical across all 3 passes on all 3 items (md5-confirmed). A
  deterministic writer is a real edge over both Claude tiers.
- **gemma4-31b:** item 1 diverged (2216 vs 2127 chars pass0 vs pass1/2); items 2, 3 byte-DET.
- **qwen3.6-27b:** byte-DET all items — but at 21-38 tps and degrading, moot.

## Recommendation

Wire **qwen3-30b-a3b-instruct** as the synthesis tier (behind a flag), with a tag post-filter to
the allowed vocab as the one required fix. It clears the discriminating over-claim floor
byte-deterministically at ~195 tps, ~$0 marginal — a strict upgrade on this stage, and it
consolidates extraction + validation + synthesis onto one local model. gemma is a viable fallback
(nondet + 5x slower). qwen3.6-27b is out on speed.

Next per the benchmark's stage order: validator shadow test (already green in S59 — run local
qwen3-30b-a3b alongside sonnet on real articles, compare catch-rate); enrichment last.

Item 2 is n=1 on the over-claim cliff; stacks (S25) is adding 1-2 more over-claim items from the
LLM stack for a second pass. Re-run when those land.
