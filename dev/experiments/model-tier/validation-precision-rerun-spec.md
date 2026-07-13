# Validation precision re-run — prompt + excerpt spec

Purpose: the S27 full-`llm` run (qwen3-30b-a3b, fault-finding prompt, 700-char
top-K excerpt) measured **10% precision / 49% false-rewrite / 63-70 recall**. That
config was built to make the model flag (leading prompt + truncated excerpt that
hides the grounding sentence), so it cannot separate model-ceiling from harness
artifact. This spec removes both confounds. If precision stays ~10% after this,
it's the model → go bigger. If it lifts, solo-local faithfulness is back on the table.

Owner split: liminal runs it on the 3090 (measuring local is their lane); this file
is the stacks-side prompt/excerpt design. Score **precision AND recall AND
fix-quality**; report determinism, never gate on it.

## Change 1 — two-stage gate (kills the flag-default)

The single-shot "is this overstated?" primes flagging. Split it. Stage 2 only runs
if Stage 1 returns UNSUPPORTED.

### Stage 1 — TRIAGE (neutral prior, SUPPORTED is expected not fallback)

```
You are checking whether ONE claim is fully supported by the source passage cited
for it. In a well-maintained library MOST claims are correctly supported —
SUPPORTED is the expected answer, not a fallback.

SOURCE PASSAGE (the full cited section):
<<FULL_SECTION>>

CLAIM:
<<CLAIM>>

Is every factual assertion in the CLAIM stated in, or directly entailed by, the
SOURCE PASSAGE? Answer with exactly one word: SUPPORTED or UNSUPPORTED.
```

### Stage 2 — LOCALIZE (only on UNSUPPORTED; forces a named span → kills vague flags AND ghost-fixes)

```
You judged the claim not fully supported. Prove it.

Quote the EXACT span of words FROM THE CLAIM that the SOURCE PASSAGE does not
support — copy the words verbatim from the claim. If you cannot quote a specific
span that literally appears in the claim, the claim is actually SUPPORTED: answer
the single word SUPPORTED and stop.

If a span was quoted, write the corrected claim — the original claim with ONLY
that span removed or trimmed to what the passage supports. The corrected claim
MUST differ from the original claim. Do not introduce any new fact.

Format exactly:
UNSUPPORTED_SPAN: "<verbatim words copied from the claim>"
CORRECTED_CLAIM: <the trimmed claim>
```

The "can't quote a span → SUPPORTED" escape hatch is the mechanical kill for both
the 539 false alarms and the 25 ghost-corrections: a flag with no nameable span is
not a flag, and a "fix" that can't change the text is not a fix.

## Change 2 — calibration anchor (CLEAN as a live verdict)

Prepend 3 worked examples to the Stage 1 prompt, drawn from HELD-OUT claims (NOT
the scoring set — no leakage): 2 that resolve SUPPORTED, 1 UNSUPPORTED with its
span. Purpose: SUPPORTED is exemplified, so the model has a concrete pattern to
match, not just an unused label. Rotate the exemplars if determinism needs probing.

## Change 3 — full cited section, not 700 chars

Retrieval returns the WHOLE cited section (the markdown section/subsection the
citation resolves to), never a top-K 700-char join. Rules:
- Resolve the citation to its source file, return the full `##`/`###` section that
  best matches the claim (whole file if the source is under ~2500 tokens).
- If no heading structure, return the full paragraph block containing the
  best-overlap unit plus its immediate neighbors. Never truncate mid-sentence.
- The invariant: the sentence that would GROUND the claim must be present in what
  the model sees. The S27 bug was that it often wasn't.

`pair-claims.py` currently does top-K units + `EXCERPT_CAP=700`; swap the excerpt
builder for a section-return (keep the claim-splitting + citation-resolution as-is).

## Change 4 — scoring (three numbers, determinism reported)

- **precision** = confirmed-real-overstatements ÷ claims the model called
  UNSUPPORTED *with a valid quoted span*. This is the number that failed (10%);
  it is the go/no-go. Target: materially above 10%; ideally ≥50%.
- **recall** = real-overstatements-caught ÷ all gold overstatements. Must not
  collapse below the current ~0.90.
- **fix-quality (ghost-correction guard)** = of caught, the fraction whose
  CORRECTED_CLAIM differs from the claim AND drops the quoted span. A
  CORRECTED_CLAIM string-equal to the claim counts as NOT caught.
- **determinism**: report over N passes; never gate.

Gold set: reuse the S27 cloud-verifier grades
(`live-diffs/validation-verify/b*.json`, per-item `gold_verdict`) as truth, or a
fresh hand-labeled precision-heavy set (many genuinely-fine claims — the S61 poison
set is recall-heavy and won't measure precision). Precision needs a denominator of
clean claims.

## Decision rule

- precision lifts materially (say ≥50%) with recall ≥0.90 → solo-local faithfulness
  is viable behind this harness; revisit the audit Step 4.5 flip.
- precision stays ~10% with a clean prompt + whole excerpt → it's the model, not the
  harness. Go to a larger local model before spending more on prompt work.

Related: #111 (summary-script must report fix-quality recall, not label recall).
