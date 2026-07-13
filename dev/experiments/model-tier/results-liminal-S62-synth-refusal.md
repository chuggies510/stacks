# Synthesis false-refusal — root cause + fix (liminal S62, stacks #109)

Closes the open item from `results-liminal-S61-synth-shadow-grade.md`: qwen3-30b-a3b false-refused
a substantive block (item-4, 5 claims). That result file hypothesized the fix was "raise the
word-count floor in the prompt." **This run falsifies that hypothesis and hands the real fix.**

Harness: local ollama on the 3900x (RTX 3090), native `/api/chat`, `qwen3-30b-a3b-instruct:latest`
(digest 19e422b02313), greedy (temp 0, seed 0), `num_ctx=16384`, 3 passes. Graduated block set:
1..5 real claims from the zenml autonomy-controls source (item-4's claims, cumulative). Determinism
is REPORTED, not a success axis (a model can be deterministically wrong — see below).

## The refusal is content-dependent and non-monotonic, not a length threshold

| claims | verdict | gold | result |
|--------|---------|------|--------|
| 1 | REFUSE | REFUSE (thin) | ok |
| 2 | REFUSE | wrote | **FALSE-REFUSAL** |
| 3 | wrote | wrote | ok |
| 4 | REFUSE | wrote | **FALSE-REFUSAL** |
| 5 | REFUSE | wrote | **FALSE-REFUSAL** |

Adding a claim flips write→refuse (3→4) and refuse→write (2→3). More content refuses while less
content writes, so **no word-count-floor prompt tweak can fix this** — the refusal is not keyed on
length. The refusal message is the bare canned line with no stated reason. It reproduces identically
across 3 passes: byte-deterministic, and byte-deterministically *wrong*. That is the point — the
refusal judgment is simply not something this model does reliably.

## When forced to write, the synthesis is clean

Removed the thin-concept refusal paragraph from the prompt; re-ran the two false-refusers:

| block | refused | recall | over-claims | citation format |
|-------|---------|--------|-------------|-----------------|
| 4c (4 claims) | 0/3 | **4/4** | **0** | bare `[slug]` ✓ |
| 5c (5 claims) | 0/3 | **5/5** | **0** | `[source: slug]` ✗ |

Every item-4 trap avoided: 65% bound + uncertainty-handling kept, autonomy-slider control-direction
not inverted (users specify, not the agent), Cox P95 kept, Cursor 28% code-acceptance not inflated
to "quality", Dropbox not universalized past its one case. The model's *synthesis* judgment
(faithful, non-over-claiming) is good — consistent with items 1/2/5 already scoring 0 over-claims
in S61. The only defects are the two mechanical gates: the refusal misfire, and the citation format
(erratic per-block: 4c emitted bare `[slug]`, 5c emitted `[source: slug]`).

## Recommendation — harness owns both mechanical gates (mirrors your item-6 fix)

1. **Drop the thin-concept refusal instruction from the local synthesis prompt.** It is a content-
   dependent misfire on qwen, unfixable prompt-side.
2. **Harness owns the thin-concept gate** — deterministic grounded-word/claim count on the concept
   block: below floor → do NOT dispatch, emit the shortfall line yourself; at/above floor → dispatch,
   the model always writes. Same shape as `claim-citation-gate.sh` for validation item-6: a
   structural decision code makes perfectly, taken away from a prompt the model follows erratically.
3. **Harness citation-format normalizer** — `[source: X]` → `[X]` (one regex post-filter, the fix
   `results-liminal-S61-synth-shadow-grade.md` already scoped). Content recall/over-claim unaffected.

**Net: qwen3-30b-a3b is a clean synthesis tier** once the harness owns the refusal gate + citation
normalizer. It handles the hard part (faithful synthesis) well; it should not be trusted with the two
structural calls. Enrichment DUP-dedup (S61) and this are the same lesson — the model's object-level
judgment holds; the mechanical bookkeeping belongs in code.

Raw bodies: `scratchpad/synth_refusal/` on the 3900x (transient). Reproduce: `run.py` (graduated set)
+ the no-refuse variant, same dir.
