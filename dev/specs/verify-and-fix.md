# Spec: verify-and-fix worker recipe (issue #109)

**Status:** approved (S25) — rollout Option A (advisory-first). Advisory window shipped 0.62.0/0.62.1.
Amended S31 (2026-10-06), see the next section; it overrides the drafter, endpoint and reviewer
named anywhere below.

## S31 amendment: breathless drafter, cloud reviewer, no soft spots

Owner decisions, S31, 2026-10-06. Nothing here needs a new script that the S25 plan did not
already name; it repoints the drafter and deletes the soft-spot path.

**1. Drafter.** The cheap tier is the breathless vLLM server, not Ollama qwen3-30b-a3b:
served model `qwen3.8-27b`, OpenAI-compatible `/v1/chat/completions`, reached from the Mini
through the existing tunnel `127.0.0.1:11436` (liminal tech-context owns the port, slots and
speed; quote it there, do not copy it here). Two settings come in through env with those
defaults: `STACKS_LOCAL_URL` and `STACKS_LOCAL_MODEL`. `local-infer.sh` gains the
`/v1/chat/completions` call shape beside its Ollama one (item 5 lists what changes) with reasoning turned off or capped, because this is a thinking model and an
uncapped reply can burn its whole budget on reasoning (liminal S91: 8,149 of 8,192 tokens).
The server has 8 slots, so the serial-only rule below is relaxed to a small fixed
concurrency (4). Measure it during the advisory batch; no parallelism code beyond `xargs -P`.

**2. Reviewer.** The cloud reviewer verifies and fixes, never regenerates (unchanged). On
Claude Code it is the agent's pinned `model: sonnet` (Sonnet 5.5 today). On Codex, which
cannot read the agent's model pin, the skill tells the session to run the reviewer as the
current Sol model at medium effort (`gpt-6.1-sol` today), set explicitly on the dispatch.
One line in `skills/using-stacks/SKILL.md`; no tier map file (#150). Validation stays a
reviewer-only stage: no local validation drafter (the S26 local validation flip was
refuted; its shadow is deleted in S31, #113).

**3. Rollout.** Option A, reusing what already ships: run ONE real catalog batch with
`STACKS_LOCAL_SHADOW=1` pointed at breathless, grade it with the shipped
`article-verifier` + `synth-verify-summary.sh`, then flip synthesis to authoritative if it
clears the floors (all block claims present, 0 over-claims). The S25 calibration does not
carry over: it graded a different drafter. Fallback when breathless is down: cloud
synthesizes from scratch as today (the flip keeps that path; no haiku tier). The always-on
Haiku A/B is deleted in S31; this advisory batch replaces it.

**4. No soft spots.** A claim tied to no source is trimmed by the validator, the same as an
overstatement, instead of being listed as a soft spot. The writer's grounded-only rule
(article-synthesizer Judgment Bias) already forbids such claims; the validator trimming them
is what makes the rule hold. Rules the trim must follow: trim only after every cited and
listed source for the article was read; a source that is missing or unreadable is reported
and its claims are left alone (an unread source is not "no source"). The `CORRECTION` row
carries the full removed sentence, so `report.md` keeps the text even when the article was
never committed. If the trim removes something the article's `routing:` line promises, the
same edit narrows `routing:`; audit finish regenerates `index.md` so lookup sees it. An
article with an unreadable source gets no `VALIDATED` receipt, so the run fails its coverage
gate instead of passing it unvalidated. Deleted with it, swept in one change: the `SOFTSPOT` verdict and
its acceptance in `assert-structure.sh`, `soft-spots.tsv` merging, carry-forward and
`git add` in `audit.sh` and the audit skill, soft-spot counts in the summary, log and commit
message, the soft-spot section of `report.md`, the soft-spot input of `enrich.sh prep` (enrich
keeps lookup misses and the empty-stack cold start), "accept as inference" wording in
enrich-stack and the enrichment agent, front-door and README mentions, and the now-orphaned
local validation harness (`validator-shadow.sh`, `shadow-validate-run.sh`,
`validation-verify-summary.sh`; validation stays a reviewer-only stage). Benchmark files and
published results stay as history. One-time cleanup per library stack, run in the library
with the library pinned: `/stacks:audit-stack <stack> --only <list>`, where the list is the
unique slugs in that stack's `dev/audit/soft-spots.tsv` that still have an article, joined
with commas (skip the stack when the list is empty), then delete that `soft-spots.tsv` only
after the audit's finish succeeded. Articles absent from the ledger had no unsourced claim
under the old validator, so a `--full` sweep buys nothing for its cost. Closes #122.
Item 4 ships in S31; items 1 to 3 build when breathless is back up.

**5. Build requirements for items 1 to 3 (S31 Codex plan review, accepted).**

- Draft into scratch, never into `articles/`, and replace an existing article only after the
  complete draft passed its filters. Snapshot the pre-update article before any writer runs;
  the drafter, any cloud writer and the reviewer all get that snapshot, and the reviewer checks
  that its unaffected claims and source paths survived.
- The reviewer leaves a fresh receipt for every dispatched slug, clean drafts included, and
  finish reconciles receipts with the existing coverage gate, so a local draft can never ship
  unreviewed.
- The advisory batch is scored against every slug in `dispatch-w2.tsv`: a missing draft,
  missing grade or failed call counts as a failure. A grade is rejected, not read as zero,
  unless its counts are nonnegative integers with `recall_present <= recall_total` and its
  claim population matches the block under the writer's conflict and sibling-link rules.
- Promotion needs the existing acceptance criteria in full, including the same-block
  comparison with a cloud article (transcription clears recall and over-claim by
  construction, #127) and the cloud-token comparison, plus one repaired scratch copy for
  every draft whose grade lists any fix, citation-only fixes included, counted in the token
  comparison. Recall is graded under the writer's own tier-conflict and sibling-link rules.
- One refusal policy: a refusal is an explicit outcome, reconciled like an article, and it
  never overwrites an existing article.
- The local drafter reads the target stack's real Topic Template, scope map and tag rule, not
  the hardcoded LLM ones.
- `article-synthesizer.md`'s fenced judgment stays a generation prompt (ADR-003); the
  reviewer role reuses `article-verifier`, with repair instructions outside the fences.
- `local-infer.sh` for vLLM changes request headers, response path
  (`.choices[0].message.content`), truncation check (`finish_reason`) and self-check
  together; every retained caller gets the model from one setting.
- Portable in-place edits (no `sed -i -E`) in the harness; the orchestrator runs on macOS.
- Codex: each dispatch seam points at one shared instruction (read the agent file, dispatch
  natively with the model and effort named in item 2).
- Declined: per-run namespacing of shadow paths (one operator, one catalog at a time).

The sections below are the S25 plan. Where they name qwen3-30b-a3b, Ollama, serial-only,
a Haiku fallback or a local validation stage, item 1 to 5 above override them.

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
