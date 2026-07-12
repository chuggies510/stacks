# Haiku behind the harness — synthesis + validation (stacks S25, issue #109)

**Why:** the earlier framing compared *raw* haiku (no harness) against *harnessed* qwen — an
unfair double standard. "Used correctly" means the same for both: the harness owns the
meta-judgment, the model does one object judgment. This run scores `claude-haiku-4-5` the
correct way (behind the harness) on the two roles where haiku had no on-record measurement,
against the same gold + floors qwen was scored on (`synthesis-benchmark.md`,
`validation-benchmark.md`).

**Method:** each item run as an isolated single-shot completion (no tools, no cross-item
context), the verbatim benchmark rubric fed per item. Synthesis items 1/2/4/5 carried the
harness's WRITE directive (claim-count ≥ 2 → write), since the refusal decision is
harness-owned; item 3 (1 claim < floor 2) is decided in code (refuse), not a model test.
Validation ran all 7 items under the gate-first prompt (STEP 1 = is the claim inline-cited).
Grading by opus (≠ writer family) against the inline trap tables.

## Synthesis (agent `article-synthesizer`, currently sonnet)

| Item | Kind | Recall | Over-claims | Verdict |
|---|---|---|---|---|
| 1 | faithful single-concept | 6/6 | 0 | PASS |
| 2 | over-claim cliff (multi-source) | 7/7 | 0 | PASS |
| 3 | thin-concept refusal | — | — | harness-decided (claim count < floor → refuse in code) |
| 4 | over-claim cliff (numeric + control-inversion) | 5/5 | 0 | PASS |
| 5 | over-claim cliff (training/eval economics) | 5/5 | 0 | PASS |

Recall 23/23 across the four written items; **0 over-claims** on all three cliffs. Every
qualifier, attribution, bound, and safeguard preserved: Ramp attributed and human-curation
kept (items 2, 5), shadow threshold kept (item 2), 65% bound + uncertainty kept and the
autonomy slider left user-controlled not agent-controlled (item 4), Cursor's 28% kept as
*code-acceptance* not generalized to *quality* (item 4), Cox's separate-LLM safeguard kept
(item 5). Floors 1–4: **clear.**

## Validation (agent `validator`, currently sonnet)

| Item | Gold | Haiku verdict | Scored |
|---|---|---|---|
| 1 | CLEAN | CLEAN | correct |
| 2 | overstatement | CORRECTION/contradiction (poison removed) | poison caught; minor label swap |
| 3 | contradiction | CORRECTION/contradiction (300→3,000) | correct |
| 4 | CLEAN | CLEAN | correct |
| 5 | overstatement | CORRECTION/overstatement ("any/zero-risk" removed) | correct |
| 6 | add-citation | CORRECTION/add-citation → zenml | correct |
| 7 | SOFTSPOT | SOFTSPOT | correct |

- **Poison recall {2,3,5} = 1.00** (floor ≥ 0.90) — clear.
- **False-correction {1,4,6,7} = 0** (floor 0) — clear. Item 6 got the citation added without
  altering wording; item 7 flagged not trimmed.
- **Action accuracy = 6/7** — the one miss is item 2 labeled contradiction vs gold
  overstatement; the replacement still removes the poison, so it is a within-CORRECTION class
  swap (minor), not a floor breach.
- **Item 6 (add-citation)** is the notable one: qwen *missed* this class under the flat prompt
  (returned CLEAN, S24/`results-liminal-S59.md`) and only caught it once the prompt went
  gate-first. Haiku catches it under the same gate-first prompt — the lever is model-agnostic.

## Head-to-head

| Axis | sonnet | haiku (this run) | qwen3-30b (liminal S59/S61) |
|---|---|---|---|
| Synthesis recall / over-claim | baseline | 23/23 · 0 | full · 0 |
| Validation poison recall / false-corr | baseline | 1.00 / 0 | 1.00 / 0 |
| Validation item-6 add-citation (gate-first) | catches | catches | catches |
| Determinism (byte-identical across passes) | no (cloud) | **no (cloud, not measured)** | **yes (byte-DET, temp 0)** |
| Marginal cost | paid | paid (cheaper than sonnet) | ~$0 (local) |

## Conclusion

Behind the harness, **haiku clears the same synthesis and validation floors qwen does.** The
earlier "haiku fails / qwen passes" split was an artifact of comparing raw-haiku to
harnessed-qwen — on extraction the *raw* over-mint was haiku 3 vs qwen 19 (qwen worse), and
that meta-judgment is the harness's job for both. The real differentiators between the two
cheap tiers are **determinism** (qwen byte-identical, haiku not) and **cost** (qwen ~$0). Not
a capability gap on these two roles. Determinism for haiku was not multi-pass-measured here
(cloud sampling makes byte-identity structurally unavailable); it is not claimed.
