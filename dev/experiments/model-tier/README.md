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

> **PROMPT-SOURCE CAVEAT (2026-07-27, #136) — every number in this table predating
> v0.77.0 was scored against a hand-typed copy of the shipping prompt, not the prompt.**
> Each benchmark used to embed its own transcription of the agent it stood for, and the
> two drifted. Enrichment is the extreme: 14 non-blank lines standing in for a 70-line
> agent, carrying **zero** of its six procedure steps. As of 0.77.0 every harness slices
> its prompt from the agent definition itself (`harness/agent-prompt.sh`, marker-fenced
> regions in `agents/*.md`), so there is one copy. Consequence: **do not compare a
> post-0.77.0 run against a pre-0.77.0 one**, and treat every pre-0.77.0 absolute figure
> as scoped to a rubric rather than to the stage. Relative orderings within a single
> pre-0.77.0 ladder are probably intact — the copy was identical across its arms.

| Stage | Agent | Benchmark | Status |
|---|---|---|---|
| Extraction | source-extractor | `extraction-benchmark.md` | Fix shipped (0.57.0 scoped slugs). Haiku validation in flight; local qwen clears behind a harness. |
| Synthesis | article-synthesizer | `synthesis-benchmark.md` | Benchmark ready (S22) — 3 items, faithfulness/over-claim + refusal floors. Awaiting liminal local scores. |
| Validation | validator | `validation-benchmark.md` | **CLOSED (S63): validation stays cloud-owned — solo-local refuted across 5 levers.** Retrieval build wired (S26, opt-in in audit Step 4.5); run at scale on the full `llm` stack (S27); precision-lever search S63. `pair-claims.py` splits each article into claims and pulls each claim's OWN cited-source excerpt (token-overlap, top-K, bullets as units); the model judges one claim + one excerpt (the offline shape). **At-scale run (45 articles, 1717 claims, qwen local → 6 cloud sonnet verifiers grading every claim against the real source): poison recall 63/70 (90%) by verdict LABEL but only 40/71 (56%) when the fix must actually remove the assertion — 25 poison claims got a `CORRECTION` label with a no-op/still-broken replacement that passes the label floor yet ships the poison. False-correction 543/1101 (49%): local wrongly alters ~half of genuinely-fine claims.** The 7-item gold-check (poison 3/3, FC 1/4) did NOT predict this — its short claims made flag==fix, hiding the label-vs-fix gap, and its tiny sample hid the false-correction blowout. **Solo-local flip decisively blocked**, and the label-based recall floor is itself unsafe (grade fix quality, not the verdict label); validation stays advisory, cloud verifier mandatory. Real audit payload: ~71 verifier-confirmed genuine overstatements/contradictions across the stack, worst in `agent-memory-systems` (11, several fabricated mechanisms the source never states). **S63 precision-lever search (removes the S27 confounds — two-stage gate, calibration anchor, full cited section): 6 levers filling all four quadrants of the {specialist,general}×{whole,atomic} 2×2, none clears the gate (recall ≥0.90 ∧ precision ≥0.50). qwen3-30b-a3b 0.38/0.22, dense qwen3-32b 0.32/0.18 (capacity walled), thinking 0.59/0.51 (helps both axes, plateaus), atomic-decompose 0.70/~0.35, Bespoke-MiniCheck-7B specialist 0.69/0.17, specialist×atomic 0.79/0.15. The trade-off is mechanical: decomposition buys recall and pays it back double in precision. Recall ceiling 0.788 (specialist×atomic), precision ceiling 0.51 (thinking-general), and no operating point holds both → the ceiling is in the data (a ~15-claim gist-preserving-overstatement core), not the substrate. **[S63 PRECISION FIGURES RETRACTED S28 — partial-denominator inflation (2.5–2.9x) + a gold a digit-counter beats; see § Key finding (validation — closed, S63). Recall figures and the CLOSED disposition stand; the closure rests on the S27 at-scale run.]** Validation cloud-owned; the shadow is advisory-only and does NOT shrink the cloud pass (best local recall 0.788 misses ~21%, so cloud is a full independent pass, not a spot-check of local flags — the cost-saving hybrid is dead).** |
| Enrichment | enrichment | `enrichment-benchmark.md` | **BENCHMARK SATURATED — cannot certify anyone (#137, S28).** Six models spanning 7.2GB to 19GB all score identically perfect: 6/6 items, all four floors, deterministic over 3 greedy passes. A gold set nothing can fail cannot rank, cannot select, and cannot certify. The predicted weak-tier signature (false-CANDIDATE on the two cliff items) appeared in **zero of six**, which is unresolvable between "the discrimination is easy at every tier" and "items 2 and 3 do not pose it." Compounds with #136: those runs used a 14-line fence standing in for a 70-line agent whose six procedure steps the fence contains none of. Do not cite any enrichment model result as a certification. Offline runner now exists (`harness/enrich_bench.py`, peer-contributed). **Live runner wired (S26, opt-in in enrich Step 4.5).** `shadow-enrich-run.sh` = harness owns Brave search + fetch, local model owns only the grounding judgment, `url-dedup-gate.sh` owns DUP. Proven live (2 gaps → 2 tier-1 candidates, 1 URL deduped). Verifier caught a tier mis-assignment. |

## Key finding (extraction)

> **POPULATION CAVEAT (2026-07-26) — every absolute number in the peer's 13-arm restraint
> ladder is PESSIMISTIC. Do not quote one as "extraction scores X" without this note.**
> The ladder ran under `MIN_SLUGS=2`, which excluded 547 of 726 eligible sources (75.3%).
> The excluded sources are the EASY ones: fan-out-1 (one concept → one article) has less
> to miss per source. Measured on the same model, prompt, seed, and D=100, with only the
> population filter moved:
>
> | arm | F1 | P | R | population |
> |---|---|---|---|---|
> | `restraint-am-qwen36-27b-d100` | 0.7029 | 0.7770 | 0.6417 | 181 (fan-out 2+, 25%) |
> | `fanout1-am-qwen36-27b-d100` | 0.7512 | 0.7736 | 0.7302 | 726 (all, 100%) |
>
> Precision is flat (inside noise); the entire move is recall, 0.642 → 0.730. The relative
> ordering BETWEEN arms is probably intact — the filter is identical across them — so the
> ladder still ranks. The absolute figures do not transfer to a production estimate.

> **CONTEXT-COST CAVEAT (2026-07-26, #133).** The scope map these findings depend on is
> ~69k tokens on hvac (250,745 chars, 663 lines), not the ~15.9k the earlier note priced.
> That earlier figure is the slug+title shape, 4.5x under the real surface. Any local-tier
> arm run against a menu that did not fit its context (two prodindex arms at num_ctx
> 8192/16384, scoring 0.435 and 0.480) measured apparatus failure, not model capability.

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

## Key finding (validation — closed, S63)

> **[RETRACTED S28, 2026-07-26 — the NUMBERS below, not the closure.]** liminal
> forensically re-scored this table and withdrew every precision figure in it. Two
> defects, either fatal alone: (1) **partial-run inflation** — their gate
> priority-sorts positives first (`run_gate.py:125`), so a run that stops early
> completes 100% of positives and a fraction of negatives; recall stays honest,
> precision reads high by construction. The 0.51 ceiling was scored over 227 of 620
> CLEAN rows (36.6% of its own negative denominator). Calibrated against the four
> runs that DID finish, restricted to the prefix the partials covered, the inflation
> factor is 2.50–2.88x across four independent gates; corrected optimistically,
> 0.51 → 0.273 and 0.35 → 0.152, and the whole table collapses into a 0.12–0.27
> band. **There is no 0.51.** (2) **The gold is a broken ruler** — on that label
> set, counting digits in the claim out-predicts every purpose-built faithfulness
> model tested (within-article AUC 0.709 for digit-count vs 0.499, chance, for
> MiniCheck-Flan-T5); overstatements average 3.39 digits/claim vs 6.54 for CLEAN,
> and 3 of 38 articles carry 68.7% of the 67 labels. A model failing R≥0.90 ∧
> P≥0.50 there failed to predict a genre marker, not to check faithfulness.
>
> **What survives.** The CLOSED disposition stands, on other evidence: the S27
> at-scale run below (45 articles, 1717 claims, full denominators, graded by six
> cloud sonnet verifiers against the real sources) is untouched by this and closes
> the stage on its own. The corrected numbers also make *this* section's own
> conclusion stronger, not weaker — nothing clears P≥0.50 by a wider margin than
> reported. Recall figures are unaffected (0.788 at specialist×atomic is a sound
> full-denominator number). What dies is the specific ceiling 0.51, the framing
> "the ceiling is in the data, not the substrate" (it may be in the *ruler*), and
> the forward lead below. **Do not carry 0.51 forward.** Original text preserved
> below unedited; see liminal's S80 retraction for the re-score.

Six levers filling all four quadrants of the {specialist,general}×{whole,atomic}
2×2, none clears the viability gate (recall ≥0.90 ∧ precision ≥0.50): no-think
MoE, thinking-mode, dense 32B, atomic-claim decomposition, a purpose-built
fact-check specialist (Bespoke-MiniCheck-7B), and specialist×atomic. Two
independent closes fell out of it:

- **Capacity is walled.** 3B-active MoE and 32B-dense land at the same poor
  point — 10× the active parameters bought nothing. The limit is not model size.
- **The wall is in the data, and the two axes trade against each other.** ~15
  overstatements are gist-preserving ("a 15-point gap *confirms* X": the gap is
  real, "confirms" is the overclaim) and read as consistent to every approach.
  Decomposition buys recall and pays it back double in precision: the strongest
  recall lever (specialist×atomic) hits 0.788 at 0.145 precision — worst of all;
  the strongest precision lever (thinking-general) hits 0.51 at 0.59 recall. No
  operating point holds both. Diversity (specialist OR atomic) lifts recall to
  0.773 but no further and at a precision cost.

**Forward lead (untried — NOT actionable as written, see the S28 retraction above).**
It is scored against the same broken gold, so "the precision axis is where every
single model fails" may be an artifact of a label set a digit-counter beats. Any
revival re-validates the gold first.

**Forward lead (untried, real mechanism).** The precision axis is where every
single model fails; the one direction with a mechanism against it is a *diverse
small-model fleet* — MiniCheck-Flan-T5-Large (770M), nli-deberta (435M), HHEM
(110M), different lineages — voted 2-of-3-to-auto-block (or single-dissent as an
advisory hint). Different lineages is the non-overlapping-blind-spot bet that
already lifted recall to 0.773; applied to precision with a vote threshold it may
be the only thing that moves it. See `results-liminal-S63-minicheck-atomic.md`.

Operational consequence: **validation is cloud-owned, and the local shadow cannot
shrink the cloud pass.** Because the best local recall (0.773) still misses ~23% of
real errors, the cloud verifier must run as a full independent pass over every
claim, not a spot-check of local's flags — so the "local flags, cloud confirms"
cost-saving hybrid does not exist for validation. The shadow stays a research/
advisory instrument (it is how this whole result was measured), gated off by
default. This generalizes: synthesis is the same faithfulness skill against the
same kind of gist-preserving trap, so it inherits the same prior — measure it, but
don't expect solo-local to clear it.

## Files

- `extraction-benchmark.md` — the extraction gold set + metric + floors (self-contained; the spec handed to liminal).
- `synthesis-benchmark.md` — the synthesis gold set: faithfulness (no over-claim) + refusal floors, 3 items (self-contained; the spec handed to liminal).
- `validation-benchmark.md` — the validation gold set: poison-recall (catch overstatement/contradiction) + false-correction (don't over-trim) floors, 7 labeled items across all verdict classes (self-contained; the offline layer, shadow test #95 above it).
- `enrichment-benchmark.md` — the enrichment gold set: false-CANDIDATE (don't accept a topical-but-non-grounding source) + tier-accuracy floors, 6 grounding-decision items (self-contained; the offline layer, live search-recall above it).
- `results-liminal-S59.md` — local-model scores + raw per-item output lines.
