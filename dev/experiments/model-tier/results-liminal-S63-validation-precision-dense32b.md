# Bigger-model lever: dense qwen3-32b — no better than the 3B-active MoE (liminal S63, stacks #109)

Addendum to `results-liminal-S63-validation-precision.md`. The decision rule's last untested
branch was "go bigger." Ran the **identical** gate/harness/gold on **dense qwen3-32b** (same
generation as the 30b-a3b MoE, ~same total params, 10× the *active* params), no-think to match
the instruct MoE, byte-deterministic (12/12 re-run). Only the model changed.

## Head-to-head (same gate, same gold, only the model differs)

| model (active/total) | recall | precision (CLEAN) | fix-quality |
|----------------------|--------|-------------------|-------------|
| S27 baseline | ~0.90 | ~0.10 | 0.51 |
| qwen3-30b-a3b (3B / 30B, MoE) | 0.379 | 0.217 | 0.84 |
| **qwen3-32b (32B dense)** | **0.318** | **0.179** | **1.00** |
| gate: pass | ≥0.90 | ≥0.50 | — |

**Dense 32B is no better — slightly worse on both axes.** 10× the active parameters bought
nothing on faithfulness. Fix-quality is perfect (when it flags, the fix is always clean), but it
flags fewer real overstatements (recall 0.32) and more clean claims (fp 96).

## What this settles

The dense-vs-MoE isolation is the point: 3B-active and 32B-active land at the **same poor
operating point**. So the wall is **not active-parameter capacity** — it is structural to local
models at the 30–32B scale on this adjudication task. "Go bigger" is exhausted at this tier; a
0.18/0.32 result gives no reason to expect a 70B to leap into the P≥0.50 ∧ R≥0.90 box (the peer's
"70B only if 32B is ambiguous" — 32B is not ambiguous, it is decisively no-better).

## Verdict against the FINAL decision rule

Both models miss both bars → **local faithfulness closed program-wide as a solo judge**:
validation stays cloud-authoritative, and don't chase local for synthesis-faithfulness either
(same skill, same wall). This closes on a twice-tested finding (MoE + dense, same generation),
not a single 3B-active data point.

## One residual lever, flagged not run (peer/operator call before final closure)

Everything above is **no-think** (required for byte-DET and to match the instruct MoE). The one
axis not tested is **test-time reasoning** — thinking-mode on a local model, the kind of
step-by-step that faithfulness-checking might actually benefit from. Not run because it (a) breaks
byte-determinism, (b) is a different lever than "bigger model," and (c) erodes the pipeline prize
even if it works (each validation call reasoning 10–30s kills the co-residence/throughput economics
the cheap-local tier exists for). Worth one cheap probe on the idle GPU before "local faithfulness:
no" goes into the audit skill — but it's the program owner's call, not mine to expand scope into.

Runner/scorer: `liminal/dev/stacks-val-precision/` (MODEL=qwen3:32b NO_THINK=1, results32.jsonl).
