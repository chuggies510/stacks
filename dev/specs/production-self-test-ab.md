# Spec: Production self-test A/B (haiku challenger)

Advances #95 (per-stage tier pressure-test) and #109 (cheapest-model-per-stage epic).
Status: DRAFT — awaiting approval before implementation.

## Problem

All four stacks workers pin `model: sonnet`, chosen by default and never re-pinned,
at ~80% of a measured $545 session. The tiering decision (#95) has stalled because
its evidence is one-off: experiments run on scratch corpora, then the data goes stale.
The existing advisory shadow harness self-tests a **local Ollama** challenger, but
local is refuted for validation and is an architecture change for the rest. The
realistic near-term re-pin is **cloud haiku** (a frontmatter edit), and it has no
continuous, real-corpus evidence.

## Goal

Make the tool **test itself on every production run**: alongside the authoritative
sonnet worker (which ships), dispatch a haiku challenger (advisory), grade **both**
by the same rubric, and append the paired delta to an accumulating log. Over many
real runs the log becomes the evidence that decides #95 — not a snapshot.

Non-goals: haiku never ships an article/correction/candidate this phase (advisory
only); no local/Ollama change; no new grader (reuse the four verifier agents); the
authoritative sonnet tier is not re-pinned by this work (that's the decision the
accumulated data later informs).

Scope: **all four worker stages** (synthesis, extraction, validation, enrichment) —
one generic seam, instantiated per stage. Synthesis is the reference implementation
and the first live exercise (the writing stack); the other three reuse the same seam
with the per-stage differences documented below.

## Key decision (user directive): ALWAYS ON

No env flag. The shadow runs on every catalog run. Two consequences:

1. **Critical-path isolation is mandatory** — and the ONLY way to get it is to run the
   whole A/B (challenger + both grading waves) **AFTER the entire catalog run**, once
   every stack's sonnet articles are filed and committed. A barrier of agents *before*
   `finish` (an earlier draft's mistake, caught by codex) can hang and block filing
   indefinitely; and 9.5 *inside* the per-stack loop lets a hung challenger block a LATER
   stack's catalog (second codex pass). So: a cheap deterministic **snapshot** of the
   concept blocks AND the shipped sonnet articles runs before each `finish` (Step 8.7, no
   agents, can't hang); `finish` commits the sonnet articles; then, after the whole run,
   the agent-driven A/B (Step 9.5) grades those snapshots. Both arms grade snapshot copies,
   so no A/B agent touches a live `articles/` file — the isolation is structural, not a
   post-hoc restore. Every A/B step is non-fatal, and the committed run cannot be undone by
   anything in it.
2. **Runs until the decision is made, then retires.** Always-on is the measurement
   phase. When the accumulated delta conclusively says "flip synthesis to haiku" (or
   "never"), the authoritative tier is re-pinned and this shadow is dropped (or flips
   to sonnet-as-challenger). It is not permanent overhead by intent.

## Design (synthesis stage)

Seam: **Step 8.7 (pre-`finish`, cheap)** snapshots each concept block `_dedup-{slug}.md`
AND the shipped article `articles/{slug}.md` to `live-diffs/ab/{LIBNAME}__{stack}__{RUN_ID_W2}/`
(`concepts/` + `sonnet/`; namespaced by library+stack+run so concurrent runs — even same
second, same checkout, different stacks — never collide) — no agents, so it can't hang.
`finish` (Step 9) commits the sonnet articles and clears the originals. **Step 9.5, run
ONCE after the whole catalog run**, grades both snapshot arms — nothing in it reads or
writes a live `articles/` file.

1. **Challenger dispatch (new, in Step 9.5).** For each concept snapshot, one `Agent`
   call, `subagent_type: stacks:article-synthesizer`, **`model: "haiku"` explicit
   override** (per the CLAUDE.md gotcha: no override runs the agent's pinned
   `model: sonnet`). Same agent, same concept block, same scope map — the changed variable
   is the model. Haiku reads the **snapshot** concept block and is dispatched as a **first
   write** (no `target_article`, even for updated slugs) so it never reads a sonnet
   article — this closes the update-contamination codex found. Output goes to
   `live-diffs/ab/{...}/bodies/{slug}__haiku.md`. The clobber guarantee is **structural**:
   both grading arms read only snapshot copies (`concepts/`, `sonnet/`, `bodies/`), so no
   A/B agent ever needs to touch a live `articles/` file. The truth copies (`concepts/`,
   `sonnet/`) are `chmod -R a-w` at snapshot time and `bodies/` is frozen the same way after
   the challenger barrier (before graders dispatch), so all three graded inputs are read-only
   during grading and a misbehaving challenger/verifier cannot corrupt what it grades. A stray
   write into the live `articles/` tree is therefore cosmetic and advisory-only; a final step
   **detects and reports** it (`git status --porcelain`) rather than blanket-resetting the
   stack (which would erase a concurrent operator edit or a legitimately-new untracked file).
   Dispatch `run_in_background`, then **barrier on completion before grading** (background is
   parallel dispatch, not detachment).
2. **Paired grading (partly new).** Reuse `stacks:article-verifier` (draft-path-agnostic
   — confirmed, "local" is only prose in its definition). Two dispatches per slug,
   both against the same concept block `_dedup-{slug}.md`:
   - haiku arm → grades `.../bodies/{slug}__haiku.md` → `.../grade-haiku/{slug}.json`
   - sonnet arm → grades the **snapshotted** shipped article `.../sonnet/{slug}.md` → `.../grade-sonnet/{slug}.json`
     (grading the authoritative output is the genuinely new measurement — today nothing
     grades it; the `synthesis.jsonl` `cloud` field is structural counts, not a verdict.)
   Reset both grade dirs (`rm -rf && mkdir -p`) before dispatch, like the existing verify step.
3. **Delta aggregation (new script `ab-synth-delta.sh`).** `jq -s` over the two grade
   dirs, joined by slug. Per slug emit one line to `live-diffs/ab-synthesis.jsonl`:
   ```json
   {"item":"<slug>","run_id":"<RUN_ID_W2>","stack":"<stack>",
    "sonnet":{"recall_present":N,"recall_total":N,"over_claims":N,"structural_pass":bool,"clears_floors":bool},
    "haiku": {"recall_present":N,"recall_total":N,"over_claims":N,"structural_pass":bool,"clears_floors":bool},
    "delta":{"recall":Δ,"over_claims":Δ,"both_clear":bool,"haiku_regressed":bool}}
   ```
   Derive every aggregate from component fields, never a self-reported boolean (the
   codex-caught bug class the existing summaries already guard). Print a run summary:
   `N slugs · haiku clears floors X/N · sonnet Y/N · haiku regressions Z · mean recall Δ`.
   A fresh `ab-synthesis.jsonl` (not the local/cloud `synthesis.jsonl`) — different data
   (paired verifier grades, not structural counts), different producer, no schema collision.

## Reuse vs new

| Reused unchanged | Genuinely new |
|---|---|
| `article-synthesizer` (both arms; model is the only variable) | The always-on shadow+grade skill step (post-`gate-w2`) |
| `article-verifier` (draft-agnostic grader) | Grading the **sonnet** arm (paired delta) |
| verify grade-JSON dirs + schema | `ab-synth-delta.sh` + `ab-synthesis.jsonl` schema |
| the `_dedup-{slug}.md` concept block as ground truth | `model: "haiku"` dispatch override + shadow output path |

## All four stages — the generic seam per worker

One pattern: dispatch a haiku challenger alongside the authoritative sonnet worker →
grade BOTH with that stage's (draft-agnostic) verifier → delta script → append to the
stage's `ab-*.jsonl`. What differs per stage is which agent, which skill/step, the
challenger's output form, and one wrinkle each.

| Stage | Skill · step | Challenger (haiku) | Verifier | Wrinkle |
|---|---|---|---|---|
| **Synthesis** | catalog · after `gate-w2` | `article-synthesizer` → shadow body file | `article-verifier` vs concept block | clean — reference impl |
| **Extraction** | catalog · at W1 (Step 4/5.5) | `source-extractor` → shadow candidate set | `extraction-verifier` vs `index.md` scope map | runs pre-dedup; writing's extraction is already done, so it rides the **next** extraction run (7th Taylor source / next stack), not a retro-grade |
| **Validation** | audit · Step 4.5 | `validator` in **verdict-only** mode (reuse the local shadow's `pair-claims` verdict stream) | `validation-verifier` forms own gold, compares | validator **edits in place**, so the challenger can't run on real articles — it's verdict-only; the NEW work is getting the **sonnet** side into the same per-claim verdict form to compare |
| **Enrichment** | enrich · Step 4.5 | `enrichment` grounding judgment on the fetched page | `enrichment-verifier` (WebFetch real page) | fires only on audit-surfaced gaps — low frequency, rides enrich runs |

Common to all four (the genuinely new measurement): today NO stage grades its
authoritative sonnet output — the challenger is graded, the shipped output isn't. The
paired A/B requires a **second verifier dispatch against the sonnet arm** in every stage.
The verifiers already accept any draft/verdict/candidate at a dispatch-given path
(confirmed draft-agnostic), so this is a new dispatch, not a new agent.

## Rollout

- **Build order:** synthesis first (reference impl, wired always-on, first live on the
  writing stack), then extraction, validation, enrichment on the same seam. Each stage is
  a shippable increment; validation is the hardest (verdict-only + sonnet-side verdict
  extraction) and comes after the two clean draft-file stages.
- Semver: **minor** per stage-batch (0.66.2 → 0.67.0 for the seam + synthesis; subsequent
  stages bump again). CHANGELOG entry each.

## Cost

Cheap arm is the haiku challenger (~⅓ sonnet rate). The added spend is **grading both
arms every run** (2× sonnet verifier dispatches per slug). Accepted per the always-on
directive; a one-sided grade is not an A/B. Revisit grading cadence only if the bill bites.

## Acceptance criteria

1. A catalog run on the writing stack produces `articles/*.md` (sonnet, filed by `finish`)
   AND `live-diffs/ab-synthesis.jsonl` with one paired-delta line per synthesized slug.
2. A forced haiku-dispatch failure (or grader failure) leaves the sonnet articles shipped
   and filed — the run reaches `finish` non-fatally, the jsonl records the failure.
3. The delta summary prints haiku-clears-floors vs sonnet-clears-floors counts for the run.
4. No haiku output is written into `articles/` or filed into `sources/` (advisory only).
5. `ab-synth-delta.sh` derives `clears_floors`/`haiku_regressed` from component grade
   fields, verified against a hand-checked slug.

## Boundaries (guardrails for the autonomous build)

**ALWAYS**
- Sonnet is authoritative: it synthesizes `articles/{slug}.md`, gates, and is filed by `finish` — unchanged from today.
- Step 8.7 (snapshot, no agents) runs **before each `finish`**; the agent-driven A/B (Step 9.5) runs **once after the whole catalog run** — that ordering keeps it off the critical path AND stops a hung challenger from blocking a later stack.
- Every shadow/grade sub-step is **non-fatal**: a haiku or grader failure logs a record and the run proceeds to `finish`.
- `ab-synth-delta.sh` **appends** to `ab-synthesis.jsonl` (accumulation) and **derives** floor clearance from component fields.
- Dispatch the haiku challenger with an **explicit `model: "haiku"`** override (the agent frontmatter pins sonnet).

**NEVER**
- Never write haiku output into `articles/` or file it into `sources/` — advisory only, shadow paths only.
- Never let the A/B corrupt, block, or fail the sonnet articles. It runs entirely after every `finish` commits, so
  it cannot delay filing; both arms grade snapshot copies (truth dirs `chmod`'d read-only) so no agent touches a live
  `articles/` file — a stray write is cosmetic and only DETECTED/reported, never blanket-reset (which would erase
  concurrent work); and haiku is dispatched first-write from the snapshot so it never reads/merges a sonnet article.
- Never truncate/reset `ab-synthesis.jsonl` (the running log is the evidence); only per-run grade dirs reset.
- Never re-pin the authoritative tier as part of this work — that is a separate decision the accumulated data informs.

**ASK FIRST**
- Flipping any stage's authoritative worker to haiku (needs the accumulated delta to justify it).
- Making the shadow permanent vs retiring it once a stage's tier decision is made.

## Commands / artifacts

- `dev/experiments/model-tier/harness/ab-synth-delta.sh <concepts-snapshot-dir> <sonnet-grade-dir> <haiku-grade-dir> <out-jsonl> [run_id] [stack]` — iterates the concept-snapshot slug set (the manifest), validates each arm independently (missing/invalid → `status`≠`ok`, never a silent drop or false-clear), derives clearance, appends. Self-check green.
- Per-run scratch (namespaced by library+stack+run): `live-diffs/ab/{LIBNAME}__{stack}__{RUN_ID_W2}/{concepts,sonnet,bodies,grade-sonnet,grade-haiku}/`.
- Accumulating log: `live-diffs/ab-synthesis.jsonl`.
- Skill steps: catalog-sources **Step 8.7** (pre-`finish` snapshot of concepts + sonnet articles) + **Step 9.5** (A/B, once after the whole run).

## Open question (one knob)

Grading cadence under always-on: grade **both arms every slug every run** (recommended —
full paired data), vs sample (every Nth slug) to cap cost. Defaulting to grade-all; flag
if the writing run's grading spend is higher than expected.
