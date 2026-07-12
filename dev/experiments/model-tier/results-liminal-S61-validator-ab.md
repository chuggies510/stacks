# Validator item-3 (and {2,3,5}) prompt A/B — local model (liminal S61, stacks #109)

Question (from S25): does the gate-first prompt regress contradiction detection vs the pre-gate-
first prompt? Direct evidence for the "split the contradiction check from the citation gate" fix,
and a proxy for whether the shipped sonnet validator (0.59.0 restructured it to gate-first too)
regressed.

Harness: local ollama on the 3900x, native `/api/chat`, `qwen3-30b-a3b-instruct-2507-q4km`,
temp 0, `num_ctx=8192`. Isolated benchmark items (single claim + cited source excerpt), NOT the
full-article context the shipped agent sees. Both prompt versions verbatim: gate-first from the
working `validation-benchmark.md`, pre-gate-first from `git show 6e097c8^`.

## Result: no prompt effect on qwen3-30b. Poison recall {2,3,5} = 1.00 on BOTH prompts, deterministic.

| Prompt | item2 (overstate) | item3 (contradiction) | item5 (overstate) | poison recall {2,3,5} |
|--------|-------------------|-----------------------|-------------------|-----------------------|
| PRE-gate-first | 3/3 catch | 3/3 catch | 3/3 catch | **9/9 = 1.00** |
| GATE-first | 3/3 catch | 3/3 catch | 3/3 catch | **9/9 = 1.00** |

Fixes are correct on both: item2 trims "consistently outperforms" → "matches ~80% agreement";
item3 corrects 300 → ~3K (30K conversations untouched); item5 adds the dropped threshold gate.

## The "0.00 miss" was two different things

- **My first-pass 0.00** (this session, before this run): a *scoring artifact*. qwen3-30b labels the
  item-3 contradiction as `CORRECTION/overstatement` (a subtype swap), and my first classifier only
  counted the literal `CORRECTION/contradiction` token. Per the benchmark's own poison-recall def
  (any CORRECTION whose replacement removes the poison and matches the source counts; a within-
  CORRECTION subtype swap is "a minor error, not a floor breach"), it is a CATCH. Re-scored subtype-
  agnostic → 1.00. The shipped agent emits a generic `CORRECTION` row anyway, so the subtype label
  never reaches the product.
- **The fork's 0.00** (separate liminal agent, reported a *bare CLEAN* with no correction): NOT
  reproduced here. A bare CLEAN is a genuine miss, distinct from qwen3-30b's correct-fix-with-wrong-
  subtype. So the fork's miss is model- or context-specific, not caused by the gate-first prompt.

## Open (to reconcile the fork's miss)

1. **Which model did the fork run?** If it was the shipped **sonnet** agent, that is the real prod-
   regression signal (can't run sonnet locally — S25 is checking prod directly).
2. **Isolated claim vs full-article context.** This A/B feeds ONE claim; the shipped validator reads
   the whole article, where a single contradictory figure is diluted among many claims and may get
   rubber-stamped. If that is the cause, the fix is claim-isolation in the validator loop, NOT the
   prompt split. Untested here — the obvious next check.

## Bottom line

The gate-first prompt did NOT regress qwen3-30b (1.00 either way). qwen3-30b is validator-viable on
this poison set (deterministic 1.00), and under the local-first/cloud-authoritative/log-the-diff
pivot it is a fine shadow candidate. If sonnet regressed, it is sonnet- or context-specific.
