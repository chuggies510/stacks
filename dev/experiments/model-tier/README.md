# Model-tier & context-efficiency test area

Tracked by **#109** (epic); extraction instance is **#95**.

Purpose: for each stacks agent stage, find the cheapest model — a cloud tier OR a
local LLM — that holds the stage's accuracy floor, and the **prompt/context
improvement** that gets it there. The recurring finding is that a stage's model tier
is usually not the accuracy blocker; the input context is.

## Method (per stage)

1. Define the stage's judgment surface — the actual decision the agent makes.
2. Build a gold-set benchmark: a few human-validated items including a tier-separating
   "cliff" item, a metric, and a floor.
3. Find the prompt/context change that lets a cheaper model hold the floor.
4. Score cloud tiers (haiku) and local models (liminal's RTX 3090 rig) against the
   floor, determinism reported.
5. Decide: cheapest tier that holds + the change that got it there.

## Stages

| Stage | Agent | Benchmark | Status |
|---|---|---|---|
| Extraction | source-extractor | `extraction-benchmark.md` | Fix shipped (0.57.0 scoped slugs). Haiku validation in flight; local qwen clears behind a harness. |
| Synthesis | article-synthesizer | `synthesis-benchmark.md` | Benchmark ready (S22) — 3 items, faithfulness/over-claim + refusal floors. Awaiting liminal local scores. |
| Validation | validator | `validation-benchmark.md` | **Retrieval build wired (S26, opt-in in audit Step 4.5); run at scale on the full `llm` stack (S27).** `pair-claims.py` splits each article into claims and pulls each claim's OWN cited-source excerpt (token-overlap, top-K, bullets as units); the model judges one claim + one excerpt (the offline shape). **At-scale run (45 articles, 1717 claims, qwen local → 6 cloud sonnet verifiers grading every claim against the real source): poison recall 63/70 (90%) by verdict LABEL but only 40/71 (56%) when the fix must actually remove the assertion — 25 poison claims got a `CORRECTION` label with a no-op/still-broken replacement that passes the label floor yet ships the poison. False-correction 543/1101 (49%): local wrongly alters ~half of genuinely-fine claims.** The 7-item gold-check (poison 3/3, FC 1/4) did NOT predict this — its short claims made flag==fix, hiding the label-vs-fix gap, and its tiny sample hid the false-correction blowout. **Solo-local flip decisively blocked**, and the label-based recall floor is itself unsafe (grade fix quality, not the verdict label); validation stays advisory, cloud verifier mandatory. Real audit payload: ~71 verifier-confirmed genuine overstatements/contradictions across the stack, worst in `agent-memory-systems` (11, several fabricated mechanisms the source never states). |
| Enrichment | enrichment | `enrichment-benchmark.md` | **Live runner wired (S26, opt-in in enrich Step 4.5).** `shadow-enrich-run.sh` = harness owns Brave search + fetch, local model owns only the grounding judgment, `url-dedup-gate.sh` owns DUP. Proven live (2 gaps → 2 tier-1 candidates, 1 URL deduped). Verifier caught a tier mis-assignment. |

## Key finding (extraction)

Over-minting was information starvation, not a weak tier. A bare 42-slug list makes
models fragment one existing article into several new sub-topic slugs; a `slug — scope`
map (the `index.md` `## Articles` routing lines) drops excess minting to 0 across every
tier (gemma 7-8→0, qwen 0-19→0). Shipped as 0.57.0.

## Key finding (validation)

Determinism is **per-task, not per-model.** `qwen3-30b-a3b` is NONDET on extraction (its recall
flips pass-to-pass) yet came back byte-DET on all 7 validation items — the validation items have
wide logit margins, so nothing flips. This softens the per-agent-roster thesis: if the DET holds
under more passes, the one fast VRAM-resident 30B could serve **both** the interactive catalog loop
(extraction) and the batch audit (validation), instead of a slow straddle for validation. Open
before pinning: (1) confirm the 30B validation DET under more passes; (2) the add-citation class
(item 6) is missed by every cheap tier — a solo cheap validator would ship true-but-uncited claims;
(3) straddle score pending as the capability ceiling / best shot at item 6.

## Key finding (validation at scale)

A 7-item offline gold-check is not a proxy for a 1717-claim run — the at-scale
pass (S27, full `llm` stack) exposed two failure modes the benchmark structurally
could not:

1. **Label-recall is a mirage.** The summary's poison recall counts a poison
   "caught" whenever the local verdict is any `CORRECTION` label. At scale, 25 of
   70 poison claims got a `CORRECTION` label whose replacement was byte-identical
   to the original (or still carried the unsupported assertion) — a
   ghost-correction that clears the ≥0.90 label floor while shipping the poison.
   Real recall (fix actually removes the assertion) is 40/71 (56%), not 90%. The
   floor must grade fix quality, not the verdict string. The gold-check missed
   this because its claims were short enough that flagging == fixing.
2. **False-correction blows out with sample size.** 1/4 on the benchmark read as
   a narrow topical-boundary weakness; at 1101 genuinely-fine claims it is 543
   (49%). Local over-flags clean content and, in a severe minority, corrupts it
   while "fixing" — polarity flips, cross-tier stat swaps, cross-source
   hallucination, and its own reasoning/meta-commentary leaking into the proposed
   article text.

Net: validation is not solo-local flippable, and running the local tier
unsupervised would both ship ~35% of real poison and rewrite half of every clean
claim. The cloud verifier that reads the real source is mandatory; the shadow
stays advisory. The run also produced genuine audit value — ~71 confirmed
overstatements now targetable for a real audit-apply pass.

## Files

- `extraction-benchmark.md` — the extraction gold set + metric + floors (self-contained; the spec handed to liminal).
- `synthesis-benchmark.md` — the synthesis gold set: faithfulness (no over-claim) + refusal floors, 3 items (self-contained; the spec handed to liminal).
- `validation-benchmark.md` — the validation gold set: poison-recall (catch overstatement/contradiction) + false-correction (don't over-trim) floors, 7 labeled items across all verdict classes (self-contained; the offline layer, shadow test #95 above it).
- `enrichment-benchmark.md` — the enrichment gold set: false-CANDIDATE (don't accept a topical-but-non-grounding source) + tier-accuracy floors, 6 grounding-decision items (self-contained; the offline layer, live search-recall above it).
- `results-liminal-S59.md` — local-model scores + raw per-item output lines.
