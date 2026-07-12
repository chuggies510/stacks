# Spec: verify-and-fix worker recipe (issue #109)

**Status:** proposed (S25). Awaiting approval before implementation.
**Supersedes the aim of:** the v0.61.0 shadow pilot (which logs a local-vs-cloud diff but
keeps cloud synthesizing from scratch — cost-neutral). This makes the cheap tier authoritative
for generation and reduces cloud to a verify pass.

## Problem

Every worker stage runs the authoritative cloud model (sonnet) to do the work *from scratch* —
synthesize each article, judge each claim, extract each source, ground each gap. That spends
Claude subscription quota on bulk generation. S25 measurements (`results-stacks-S25-haiku.md`,
`results-liminal-S61-*.md`) show a cheap tier clears the accuracy floors behind the harness:
local qwen3-30b-a3b (~$0, off-quota) or haiku (subscription fallback).

## Goal

Move bulk generation to the cheap tier; reduce the cloud model to **verify-and-fix**. Free
Claude quota for work that needs Opus. Success = good output that clears the floors at lower
cloud-token spend — not byte-identical output (determinism retired, see
`DESIGN-local-tier.md` § Aim).

## Non-goals

- Byte-identical output.
- Eliminating cloud calls — cloud still verifies every item; it shrinks from *generate* to *check*.
- The hard tail — verifier reliability degrades with difficulty (below); this is a moderate-band
  tool, proven on synthesis first.

## The recipe (generalized, all four stages)

```
cheap tier does ONE object judgment (draft / judge / extract / ground), SERIAL on the local GPU
  → deterministic harness gates own every meta-decision
      (refusal gate, tag filter, citation normalizer, slug pre-match, URL dedup)
  → authoritative cloud model VERIFIES the cheap output against the stage's floors,
      with a SPECIFIC free-form critique, and FIXES only what fails (≤2 rounds), in place
  → existing gate (gate-batch.sh) enforces freshness + shape, unchanged
```

## Library-grounded constraints (from /lookup — LLM stack)

From *Generator-Verifier Gap in Test-Time Scaling*, *Self-Correction Loops*, *Wiring an
LLM-Judge Tier Behind a Deterministic Gate*:

- **A weak drafter is the EASY case for the verifier.** Weak generators make coarse errors that
  are easy to catch; strong generators make subtle errors that are hard to catch
  (generator-strength paradox). Gap compression: weak-vs-strong generator gap shrank **75.7%**
  under a shared verifier. This is the quantitative basis for "local draft + cloud verify ≈
  cloud generate."
- **Verifier ≠ drafter family.** A model grading its own family inflates scores (self-enhancement
  bias). qwen-draft + sonnet-verify is clean (different families); **haiku-draft + sonnet-verify
  shares the Claude family** — weaker separation. → **qwen is the default drafter**, not only for
  cost. If haiku drafts (local box down), note the weaker check.
- **Specific, free-form critique; cloud does the fix.** Bare "wrong, redo" reproduces the failure
  (blind retry is not self-correction). The cloud verifier names the exact defect (which claim
  over-claims, the trim) and fixes it *itself* — never loops the weak model. Keep the critique
  free-form; a schema-constrained critique triggers "structure snowballing" (format satisfied,
  reasoning stops). Cap at **≤2 rounds** (diminishing returns after 1–2).
- **Advisory-then-gate.** A verifier ships non-blocking first, earns the right to gate only after
  calibration against the floors. The current shadow is that advisory stage.
- **Moderate-band only.** Verifier reliability falls as difficulty rises; the hardest items may be
  permanent-advisory. Prove the machinery on synthesis (structural, moderate).

## Stage 1: Synthesis (first slice)

### File-flow change (grounded in `scripts/pipeline/catalog.sh` + `skills/catalog-sources/SKILL.md`)

Today: `dedup` writes `_dedup-{slug}.md` + `dispatch-w2.tsv` + `RUN_ID_W2` → the SKILL dispatches
sonnet `article-synthesizer` per slug → `articles/{slug}.md` → `gate-w2` → `finish`.

Verify-and-fix:
1. `dedup` — unchanged.
2. **NEW local-draft phase** — qwen drafts `articles/{slug}.md` **serially** (`/api/chat`,
   `stream:false`, `temp 0`, `keep_alive:-1`, `num_ctx 4096`), with the harness gates applied
   (refusal gate, `tag-postfilter.sh`, `citation-normalizer.sh`). This is the existing
   `shadow-synth-run.sh` loop **repointed from `live-diffs/bodies/` to `articles/`**.
3. **Cloud verify+fix** — `article-synthesizer` agent's role flips from "write from block" to
   "verify the draft against the block, fix only defects in place." Still per-slug, still ≤25/wave.
4. `gate-w2` — unchanged (freshness vs `RUN_ID_W2` holds: the local draft writes after it).
5. `finish` — unchanged.

### Agent change

`agents/article-synthesizer.md`: input becomes concept block + existing local draft. Task: confirm
every block claim is present and not over-claimed, structure valid; **fix only defects** (Edit),
leave a clean draft untouched; free-form critique; ≤2 rounds. (Per the subagent-Write gotcha, the
agent MODIFIES via Edit, never rewrites the file.)

### Throughput (measured on the box, liminal S25)

197 tok/s; 5s cold load once, then ~3s/slug warm; **~65s for a 20-slug batch, serial, off-quota**.
`keep_alive:-1` keeps the model resident after slug 1. `num_ctx 4096` is pure margin (block+rubric
≈ 224 prompt tok, ~400-word article ≈ 530 gen tok). Sustained large batches trim to ~180 tok/s
under the box's fan-noise governor. OLLAMA_NUM_PARALLEL concurrency is unmeasured — **serial only**.

### Rollout (the one decision to confirm)

- **Option A — advisory window first:** cloud keeps synthesizing authoritatively for one real
  batch; ADD a cloud verify pass over the local draft that only LOGS "would clear the floors / what
  I'd fix." Watch it on real blocks, then flip to authoritative. Safest; costs one batch of extra
  cloud verify.
- **Option B — direct flip with fallback:** local draft becomes the article now; cloud verifies+
  fixes; keep the old sonnet-from-scratch path behind a flag for one A/B compare. Faster; leans on
  the offline floor-clearance we already measured + gate-w2's shape floor.

## Acceptance criteria

- Every `dispatch-w2` slug has a fresh `articles/{slug}.md` draft after the local phase.
- Post cloud verify+fix, every article passes `gate-w2` (shape + freshness) AND clears the
  synthesis floors (all block claims present, 0 over-claims) — spot-checked on the over-claim cliffs.
- Cloud output-token spend per batch < baseline sonnet-from-scratch (measure verify vs generate).
- Sample compare: verify-and-fix articles are as good as sonnet-from-scratch on the same blocks.

## Risks

- Verify misses a subtle over-claim (generator-verifier gap) → moderate-band only, advisory-first,
  `gate-w2` shape floor stays, spot-check cliffs.
- haiku-drafter self-enhancement under sonnet verify → default qwen drafter.
- Local box down / busy (shared with the 6h curator) → fall back to haiku draft, or straight
  sonnet-synthesize.
- Serial only (concurrency unmeasured) → 65s/20 is the committed number.

## Stages 2–4 (same recipe, after synthesis lands — sketch, not this slice)

- **Validation:** local judges each claim per-item; cloud verifies the verdicts (esp. the local's
  CLEANs, where a miss = poison) and fixes; harness keeps per-claim isolation. Watch structure-
  snowballing on the meta-judge.
- **Extraction:** local extracts with deterministic slug pre-match; cloud verifies the concept set
  (recall gaps; over-mint already harness-owned) and fixes.
- **Enrichment:** local runs the full agentic loop (search+fetch+judge, proven S59/S60 + S25);
  cloud verifies the CANDIDATE grounding; harness owns URL-dedup set-membership.
