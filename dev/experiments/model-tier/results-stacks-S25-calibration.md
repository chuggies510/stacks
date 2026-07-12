# S25 live advisory calibration — the shipped verify-and-fix apparatus, end to end

**What this measures (and how it differs from the earlier results files).** The
`results-liminal-S61-synth*.md` and `results-stacks-S25-haiku.md` files hand-scored
the drafts. This run instead exercises the **shipped 0.62.x wiring itself** on real
`llm` concept blocks: qwen drafts serially on the box GPU via `synth-shadow.sh`, the
`article-verifier` sonnet agent grades each draft against the block, and
`synth-verify-summary.sh` derives the go/no-go from the grade JSONs. It is the
integration test that authorizes the flip to authoritative (ADR-002 slice 1b) — it
confirms the apparatus works, not just that qwen can draft.

**Setup.** Drafter `qwen3-30b-a3b-instruct` (temp 0, keep_alive:-1, num_ctx 4096,
`/api/chat`), serial on the single 3090 (curator paused by liminal to free the GPU).
Verifier: cloud sonnet — a different family from the drafter, so no self-enhancement
bias. Blocks extracted from `synthesis-benchmark.md` items 1–5 into
`live-diffs/blocks/`.

**Draft batch wall time: 16s for 5 blocks, serial, cold-load included** (faster than
the ~65s/20 estimate — a3b cold-loads and generates well under the projection at this
batch size).

## Result — 4/4 article items clear the floors; refusal honored

| Item | slug | recall | over-claims | structural | citation-fixes | clears |
|------|------|--------|-------------|------------|----------------|--------|
| 1 | llm-evaluation-frameworks | 6/6 | 0 | pass | 0 | ✓ |
| 2 | production-eval-systems | 7/7 | 0 | pass | 0 | ✓ |
| 4 | production-agent-autonomy-controls | 5/5 | 0 | pass | 0 | ✓ |
| 5 | agent-training-evaluation-economics | 5/5 | 0 | pass | 0 | ✓ |
| 3 | judge-verbosity-monitoring | — | — | correct refusal | — | ✓ (restraint) |

`synth-verify-summary.sh` over the 4 article grades: `clears floors: 4/4`, over-claims
total 0, recall misses 0, structural fails 0, citation fixes 0. Item 3 is excluded from
the article-floor aggregate and scored on the restraint floor alone (a refusal fed to a
recall grader would falsely read as recall 0/1); qwen emitted
`Concept judge-verbosity-monitoring: insufficient claims — article not written.` — the
correct refusal.

## What the verifier flagged (non-floor)

Every grader independently noted the drafts are **terse** — close to the block claims
concatenated with citations appended, ~150 words against the 300–800 word house target,
one run-on paragraph. This is faithful (0 over-claims is the whole point — the model
added nothing) but thin. It is a **quality knob for the authoritative cloud pass to
enrich**, not a floor breach: the synthesis floors grade fidelity (recall + 0
over-claims + structure), and fidelity is perfect. Note for slice 1b: the verify-and-fix
cloud step may optionally expand thin-but-faithful prose, but that is an enhancement,
not a fix — do not let it regenerate and reintroduce over-claim risk.

## Caveat (why the cloud verify stays as the safety net)

These are the 5 in-distribution benchmark items qwen was effectively tuned against, not a
fresh held-out set. A clean sweep here proves the apparatus and the recipe on known
blocks; it does not prove qwen on unseen blocks. That is exactly why ADR-002 keeps the
**cloud verify-and-fix as a mandatory safety net** on every item — the generator-verifier
gap means a weak drafter's coarse errors are the easy case for the verifier, and the
verifier is the backstop for the blocks this batch didn't cover.

**Authorizes:** ADR-002 slice 1b (flip synthesis to local-authoritative + cloud
verify-and-fix). Grade JSONs: `live-diffs/verify/*.json`. Drafts: `live-diffs/bodies/*__local.md`.
