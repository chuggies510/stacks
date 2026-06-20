# Design: `enrich-stack` skill + `enrichment` agent

**Date:** 2026-06-19
**Issue:** #64 (Enrichment skill: acquire sources to fill audit soft spots)
**Status:** approved (design), pending implementation plan

## Problem

The stacks pipeline is pull-only. `source-extractor`, `article-synthesizer`, and
`validator` all operate on sources the user has already dropped in
`sources/incoming/`. Nothing ever goes out and *finds* material.

`/stacks:audit-stack` identifies **soft spots** — a written claim in an article
that has no cited source backing it — and lists them in `dev/audit/report.md`.
Closing them is entirely manual: a human reads the report, web-searches for a
source that grounds each claim, drops it in `incoming/`, and re-catalogs. One
`audit-stack llm` run produced **35 soft spots**; backfilling by hand is the
bottleneck.

This adds the missing acquisition step, slotting between the two existing skills:

```
audit-stack   →   enrich-stack   →   catalog-sources
(finds gaps)      (acquires sources)   (ingests them)
```

## Scope

- **Soft-spot mode only.** Coverage-edge mode (topics the stack omits entirely)
  is deferred to a follow-up, as issue #64 itself suggests.
- Four files change, plus one gate shape:
  1. `agents/enrichment.md` — new per-gap acquisition agent.
  2. `skills/enrich-stack/SKILL.md` — new orchestrator skill.
  3. `agents/validator.md` — emit a structured, verbatim soft-spot record (contract fix).
  4. `skills/audit-stack/SKILL.md` — persist `dev/audit/soft-spots.tsv` (machine input).
  5. `scripts/assert-structure.sh` — add an `enrichment-findings` shape case.

## Division of labor

Mirrors the existing `audit-stack` → `validator` split: the agent does the
nondeterministic web work and writes a findings file; the parent skill owns
batching, gates, dedup, the operator-approval gate, and every repo write.

```
/stacks:enrich-stack {stack}      ← skill: read soft-spots.tsv, stale-check,
        │                            batch, dispatch, aggregate, approve, stage
        │  dispatches (CAP-slice, parallel)
        ▼
   enrichment agent                ← per gap: search → fetch → verify → tier →
        │                            dedup → one findings row
        ▼
   dev/enrich/_enrich-${TAG}.md    ← findings file (parent aggregates, then rm)
```

## The audit→enrich data boundary (codex #1 — the load-bearing fix)

`enrich-stack` must NOT parse `report.md` markdown. Its soft-spot bullets are
`` - `slug` — "claim" — reason ``, and claims routinely contain em-dashes,
quotes, and parentheses, so splitting on ` — ` is unreliable. The structured
data already exists transiently in the validator's per-batch files, but
`audit-stack` `rm`s it after building the report. The fix:

**`validator` output contract changes** from a 3-field blended description to a
4-field record with the verbatim claim:

```
SOFTSPOT<TAB>slug<TAB>claim<TAB>reason
```

- `claim` is the **complete, verbatim** substantive sentence from the article
  body (newlines/tabs normalized to spaces), not a shorthand. Needed for precise
  search, the staging-time re-verify, and the stale-check.
- `reason` is why it is soft (one line).
- `CORRECTION` lines are unchanged (still `CORRECTION<TAB>slug<TAB>description`).

**`audit-stack` persists `dev/audit/soft-spots.tsv`** — the aggregated SOFTSPOT
lines (`slug⇥claim⇥reason`) — as a durable, machine-readable artifact alongside
the human `report.md`. The report is rendered from the same data (join claim +
reason for the bullet). The `rm -f _audit-*.md` stays; the `.tsv` is the new
durable output. Committed with the report.

## The `enrichment` agent (`agents/enrichment.md`)

```yaml
name: enrichment
tools: Glob, Grep, Read, Write, WebSearch, WebFetch
model: sonnet
```

No `Edit`/`Bash`: the agent never mutates an article or the repo, only writes
its own findings file. (Web fetches during research; the *skill* does the
approved staging into `incoming/`.)

**Input** (per batch, in the dispatch prompt):
- Assigned gaps: a slice of `(gap_id, slug, claim, reason)` rows from
  `soft-spots.tsv`. `gap_id` because one article can hold many gaps
  (`lora-prompt-loss-weight` has 4) — slug alone collides.
- STACK.md source-hierarchy (tiers) + scope section.
- Filed-sources listing (slug + title + url from frontmatter) for URL dedup.
- `$STACK`, `$BATCH_TAG`.

**Process, per gap:**
1. Derive a targeted query from the verbatim claim (scope disambiguates).
2. `WebSearch`; take the best 1-3.
3. `WebFetch` them; **verify by falsification** — does the source *state this
   specific claim*, not merely cover the topic? Topically-adjacent ≠ grounding.
4. Assign a tier per STACK.md (1 vendor doc … 4 forum).
5. Dedup: if the best candidate's URL is already in the filed-sources listing →
   `DUP` (cite the existing source; no fetch needed).

**Four verdicts** (one record per gap — the agent picks the single best source;
not a candidate list for the operator to adjudicate):

| Verdict | Definition | Operator action |
|---|---|---|
| `CANDIDATE` | directly supports the claim, tier 1-3 | approve → stage → re-catalog |
| `WEAK` | directly supports, but only tier 4 (forum/general) | decide if acceptable |
| `DUP` | an **already-filed** source's URL grounds it | add the citation manually |
| `NOSOURCE` | searched candidates do not support it | tighten claim, or accept as inference |

Tool/network failure is a `NOSOURCE` whose reason says "search/fetch failed" —
not a 5th verdict, but distinguishable so a transient failure is not read as a
permanent epistemic conclusion.

**Output:** one findings file `dev/enrich/_enrich-${BATCH_TAG}.md`,
tab-separated, one row per gap, every field stripped of tabs/newlines:

```
KIND<TAB>gap_id<TAB>slug<TAB>source_ref<TAB>url<TAB>tier<TAB>title<TAB>quote
```

- `source_ref`: for `DUP`, the existing filed-source slug/path; else empty.
- `url`/`tier`/`title`/`quote`: populated for CANDIDATE/WEAK/DUP; for NOSOURCE,
  `quote` holds the short search summary / failure reason.

Three worked examples in the agent body: CANDIDATE, DUP, NOSOURCE.

**Judgment bias:** verify the source grounds *the claim*, not the topic; default
to NOSOURCE/WEAK when unsure (a wrong citation is worse than an honest soft spot
— mirrors the validator); never fabricate a URL or a quote.

## The `enrich-stack` skill (`skills/enrich-stack/SKILL.md`)

- **Step 0-1 — telemetry + gate.** `catalog.md` present, STACK arg, STACK.md
  present, **and `dev/audit/soft-spots.tsv` present** (else: "run
  `/stacks:audit-stack {stack}` first"). Empty TSV → exit "nothing to enrich."
- **Step 2 — read context.** STACK.md (tiers + scope); build the filed-sources
  listing for dedup.
- **Step 3 — stale-check (codex #3).** For each TSV row, confirm
  `articles/{slug}.md` exists and the verbatim claim still occurs in it
  (`grep -F`). Drop stale rows, report the count; if all stale → "re-run
  audit-stack." Assign `gap_id` = line index of the surviving rows.
- **Step 4 — dispatch.** `enrichment` over gap batches, **CAP=12** (≈3 agents
  for 35 gaps). Web calls within an agent are serial, so peak concurrency ≈ agent
  count, not gap count — no wave machinery needed. Parallel dispatch; gate each
  expected `_enrich-${TAG}.md` with `gate-batch.sh` + the new
  `enrichment-findings` shape.
- **Step 5 — aggregate + dedup-by-URL (codex #10).** Collapse findings across
  batches; if two gaps picked the same canonical URL, stage once and list every
  gap it serves.
- **Step 6 — operator approval (codex #9).** Present a table (verdict / slug /
  tier / url / quote). **Nothing is written until the operator approves a
  displayed list.** Default proposal: stage all `CANDIDATE`s; `WEAK`s require
  explicit opt-in; `DUP`/`NOSOURCE` are never staged. Modes: approve all /
  select / include weak / cancel. (Per the AskUserQuestion 4-option cap: present
  the table and confirm; don't picker-spam.) On cancel: clean up
  `dev/enrich/_enrich-*.md`, write nothing.
- **Step 7 — stage approved (codex #7, #8).** For each approved URL, `WebFetch`
  into `sources/incoming/` as a readable text file with provenance frontmatter:

  ```yaml
  ---
  title:
  url:
  publisher:
  fetched:        # date +%Y-%m-%d
  tier:
  supports_gap:   # slug(s)
  ---
  ```

  Then the fetched text/excerpt. Filenames via `collision-dest.sh`.
  **Re-verify:** confirm the supporting quote still appears in the re-fetched
  content; absent/failed fetch → warn and skip that one (a CANDIDATE verdict does
  not guarantee staging success).
- **Step 8 — report (codex #11, #12).** Staged count + next step ("run
  `/stacks:catalog-sources {stack}`, then re-audit to confirm gaps cleared").
  List `DUP`s as concrete manual actions (`slug → existing-source-slug → quote`)
  — do **not** imply enrich-stack closed those gaps. List `NOSOURCE`s for the
  operator to tighten. **No auto-catalog, no commit:** staged files sit untracked
  in `incoming/` exactly like a manual source drop; `catalog-sources` commits
  them when it files them. No persistent enrichment ledger — each run derives its
  work from the latest audit artifact.

## Gate shape (`scripts/assert-structure.sh`)

Add an `enrichment-findings` case: the file is non-empty and every line is a
tab-separated record whose first field is one of
`CANDIDATE|WEAK|DUP|NOSOURCE`. Keeps enrich gating consistent with the rest of
the pipeline (`concept-batch`, `article-md`, `article-validated`).

## Deliberate divergences from issue #64

1. **Agent embodies deep-research's *method*, doesn't invoke the skill.**
   `deep-research` is a fan-out harness producing a *cited report*, not a staged
   source, and is heavyweight per gap. Per-gap grounding is 2-3 web calls inline.
2. **Agent returns findings; the skill stages after approval** (issue had the
   agent fetch into `incoming/` directly) — keeps operator approval *before* any
   repo write and matches the validator's findings-file split exactly.
3. **Soft-spot mode only**; coverage-edge deferred.

## Rejected / deferred review points

- **Content-aware internal dedup** (search filed-source *text* per gap to find an
  existing grounding source): deferred. The audit already checked claims against
  cited sources; an *uncited* filed source grounding a soft spot is rare and
  low-yield. `DUP` stays URL-match only (covers the real re-drop bug).
- **Multi-candidate rows per gap**: rejected. The agent picks the single best
  source; a list to adjudicate defeats the issue's "find *one* source" intent.

## Versioning

Plugin → minor bump (new skill + agent): `0.29.0`. `validator` and `audit-stack`
each carry a minor change (output contract / new artifact). One CHANGELOG entry,
`plugin.json` + `marketplace.json` synced.

## Verification

- `validator` emits 4-field SOFTSPOT with a verbatim claim; `audit-stack` writes
  a non-empty `soft-spots.tsv` on a stack with known soft spots (re-run
  `audit-stack llm`; expect 35 rows).
- `enrich-stack llm` end-to-end: stale-check drops nothing on a fresh audit,
  dispatches, produces findings, the approval gate blocks writes until confirmed,
  approved sources land in `incoming/` with provenance frontmatter and a
  re-verified quote.
- Removing the verbatim-claim change makes the stale-check `grep -F` fail —
  a red-when-removed check on the contract fix.
