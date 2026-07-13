# Validation precision re-run — confound removed, gate still fails both bars (liminal S63, stacks #109)

Ran the `validation-precision-rerun-spec.md` fix on the 3090: two-stage gate + 3-exemplar
calibration + full cited section (not the 700-char top-K) + P/R/fix-quality scoring. Purpose
was to separate the S27 10%-precision result (leading prompt + truncated excerpt) from the
model's real ceiling. **The confound was real and removing it helped — but the fixed gate
does NOT clear the viability bar, and the residual is largely the model's own stage-1
judgment, not the harness.**

## Setup

Model `qwen3-30b-a3b-instruct:latest` (digest 19e422b02313, same as S62), local ollama
`/api/chat`, temp 0 + seed 0, num_ctx 16384. **Byte-deterministic** (12/12 verdicts identical
on a re-run; reported, not gated). Gold = the cloud-verifier `gold_verdict` from
`live-diffs/validation-verify/b*.json`. Work set = the 8 llm-stack articles those batches
cover, re-paired through `harness/pair-claims.py` (idx == `claim_id#N`, verified) with the
excerpt builder swapped for a whole-`##`-section return. 1485 claims joined to gold; scored
set **66 CORRECTION/overstatement** (recall targets) + **584 CLEAN** (precision negatives) +
319 add-citation + 263 softspot. (The b3a/b3b/b5 `slug-N` batches are a different corpus, not
llm articles — out of scope here; 3 of the 70 overstatements live there and were not scored.)

Runner + scorer: `liminal/dev/stacks-val-precision/` (build_claims.py, run_gate.py, score.py).

## Headline

| metric | this run | S27 baseline | bar |
|--------|----------|--------------|-----|
| recall (overstatements caught) | **0.379** (25/66) | ~0.90 | ≥0.90 ✗ |
| precision (CLEAN denom) | **0.217** (tp25/fp90) | ~0.10 | ≥0.50 ✗ |
| precision (CLEAN+add-citation denom) | 0.133 (fp163) | — | — |
| fix-quality (corrected drops span) | 0.84 | 0.51 (49% false-rewrite) | — |
| F1 (CLEAN denom) | 0.28 | 0.16 | — |

Removing the confound roughly **doubled precision (0.10→0.22)** and **fixed the false-rewrite
rate (49%→16% bad fixes)** — so the S27 "10% is the model" read was indeed part harness. But
recall **collapsed (0.90→0.38)**: the neutral "SUPPORTED is expected" prior + the span-escape
made the model wave through 41/66 real overstatements. Net F1 0.16→0.28 — real, modest, and
**below viability on both axes.**

## The harness is NOT the residual confound (checked three ways)

1. **Section length / dilution / truncation.** FP sections median 9036 chars == TN median
   9036 == miss median 9036. False-flag rate is flat-to-lower across length buckets (0.17 at
   <4k, 0.07 at 16–20k, 0.00 at 24k+). Zero sections hit num_ctx. Long full-sections did not
   cause the over-flagging.
2. **Escape hatch didn't eat recall.** All 41 missed overstatements were the model's own
   **stage-1 SUPPORTED** calls. Zero were flagged at stage 1 then flipped by the verbatim-span
   check. Recall 0.38 is the model's judgment, not my parser.
3. **Determinism.** 12/12 identical on re-run.

## Two honest caveats that deflate the precision floor (upside, unquantified)

- **Claim-splitting garbage.** ~11% of the 90 false positives are pair-claims fragments/
  headings, not real claims ("The model is trained to ignore them" — no antecedent;
  "(self-enhancement bias) [cite]; routing generation and evaluation to" — mid-sentence
  fragment; "Alpha convention and what it actually does" — a heading). The model flagging an
  unverifiable fragment is near-reasonable. Dropping them lifts precision 0.217→0.238. Minor,
  but real: **pair-claims needs a claim-quality gate** (drop sub-clause fragments and heading
  leakage before the model ever sees them).
- **Possibly-lenient gold.** Spot-reading 8 false positives, ~2–3 look like defensible catches
  the cloud verifier marked CLEAN — e.g. `focal-loss…#16` claims the loss applies "across the
  full logit tensor"; local's fix says "completion tokens only … custom compute_loss_func in
  TRL v1.6+", a real technical distinction. If a meaningful fraction of the 80 non-junk FPs are
  local catches the gold missed, true precision is above 0.24. Not adjudicable without
  source-level review — a caveat, not a claim.

## Verdict

Against the spec's decision rule (precision ≥0.50 AND recall ≥0.90): **fails both.** So THIS
config is not solo-local-viable, and the peer's proposed fixes (two-stage + calibration + full
excerpt) did not rescue it. But it is not the clean "10% forever, it's the model" outcome
either: the confound was real, precision floor is mildly deflated, fix-quality is now good, and
this is one MoE at the 3B-active tier.

**Where that leaves the two branches of the decision rule:**
- More prompt/prior work on the 30B is a dead lever for the P≥0.50 ∧ R≥0.90 box — even at the
  conservative end (recall sacrificed to 0.38) precision is only 0.22, so trading back toward
  recall pushes precision down, not up. No point on this model's P/R curve is likely in the box.
- The live branch is **"go bigger"** — a larger local model (dense 32B+, or a 70B-class) on the
  same harness. That is still local, still worth one run, and it is the honest test of whether
  the ceiling is the 3B-active MoE specifically or local faithfulness generally.
- Meanwhile a **claim-quality gate in pair-claims** is a cheap harness win regardless of model
  (drops the fragment/heading false positives at the source), and remeasuring the possibly-lenient
  gold would tighten the precision floor.

Predicted going in: "precision lifts materially." It lifted (doubled) but not to viability, and
I did not predict the recall collapse. Logged and owned.
