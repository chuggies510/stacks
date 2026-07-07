# Article contract

The one checked-in definition of what an article file (`articles/{slug}.md`) contains
and what a W1 concept-extraction block looks like. Every stage that produces or
consumes this shape points here instead of restating it — the same role
`references/reference-tier.md` plays for the deep-reference tier. `scripts/assert-structure.sh`
is the executable enforcement: its `article-md`, `dedup-md`/`concept-batch`, `dedup-meta`,
`audit-findings`, and `enrichment-findings` kinds are the machine check for the
fields below. A field added here without a matching grep in `assert-structure.sh` (where
the field is machine-checkable at all) is drift waiting to happen — keep the two in sync.

## 1. Article frontmatter schema

`articles/{slug}.md`, written by `article-synthesizer` (first write or update), read by
`validator`, `assert-structure.sh`, `scripts/regenerate-moc.sh`, `scripts/normalize-tags.sh`,
and `/stacks:lookup`.

| Field | Type | Writer | Reader(s) | Machine-enforced? |
|---|---|---|---|---|
| `last_verified` | string, `""` or `"YYYY-MM-DD"` | `article-synthesizer` (sets `""` on write/update); `validator` (sets to today) | `assert-structure.sh` `article-md` (key must exist — any value, including empty, passes). NOT the audit gate's coverage signal since T7: the gate reconciles a per-article `VALIDATED<TAB>slug<TAB>RUN_ID` receipt row (`audit-findings` kind + `check-coverage.sh --verdict VALIDATED`), which proves per-article coverage a wall-clock date could not. `last_verified` is still written for provenance. | Yes — key presence (`article-md`) |
| `updated` | date, `YYYY-MM-DD` | `article-synthesizer` | none currently | No — required by convention only; zero readers found (grep across `scripts/`, `agents/`, `skills/` turns up only the writer). Same shape as the now-dead `extraction_hash` field. Kept required per spec Decision 4 rather than dropped in this pass — flagged below, not silently reconciled. |
| `sources` | YAML list of bare `sources/{publisher}/{file}.md` paths | `article-synthesizer` | `validator` (resolves each `[source-slug]` citation against this list); `/stacks:lookup` Step 7 (collects primary-source citations) | No (no grep kind checks list contents; `article-md` doesn't check this key) |
| `title` | string, human-readable | `article-synthesizer` | `assert-structure.sh` `article-md`; `/stacks:lookup` (cites articles by title) | Yes — key must exist |
| `routing` | one-line plain-text string, asker's-words description | `article-synthesizer` | `scripts/regenerate-moc.sh` (the MoC line per article); `/stacks:lookup` Step 6 (query-to-article recognition) | No |
| `tags` | YAML list, values drawn from `STACK.md`'s `allowed_tags:` | `article-synthesizer` | `scripts/regenerate-moc.sh` (groups the MoC by `tags[0]`); `scripts/normalize-tags.sh` (drift check against `allowed_tags:`) | No (no grep kind checks tag values; enforcement is `normalize-tags.sh`, not `assert-structure.sh`) |

`extraction_hash` is **dead**: it was part of a since-removed skip-list flywheel
(stacks#77/CHANGELOG), stripped from all 930 corpus articles, and never read by any
current script or agent. Do not reintroduce it. Verified empirically: `grep -rln
extraction_hash */articles/*.md` across the library corpus returns zero files.

## 2. Source-ref format

Canonical form is **bare**: `sources/{publisher}/{file}.md` — never stack-prefixed
(`{stack}/sources/{publisher}/{file}.md`). `article-synthesizer` writes exactly what
`dedup-extractions.py` normalizes into `source_paths:` (already stripped of any leading
`<stack>/` or absolute prefix, stacks#65) — never prepend the stack name.

The corpus currently carries **both** forms (stacks#77, a live migration tracked as a
sub-issue of this seam, not fixed by this doc): older articles predate the bare-only
rule. `/stacks:lookup` Step 7 resolves either form defensively for that reason — that
defensive fallback is a corpus-migration accommodation, not a second valid target form.
New writes are always bare.

## 3. Tier semantics

**Target semantics: tier attaches per `source_path`, not per concept.** A concept
block can merge claims from sources of different tiers (e.g. a Tier-1 standard and a
Tier-3 blog post both discussing the same topic); the merged concept's claims still
need to trace back to their own source's tier for `validator` conflict resolution
(higher tier wins) and for `article-synthesizer`'s STACK.md-hierarchy weighting.

**Current implementation disagrees with this target — flagged, not silently fixed
here (out of scope for this doc/scripts-untouched task).** `scripts/dedup-extractions.py`
stores a single `tier` value per **slug**, taken from the first-seen contributing block
(`slug_tier[slug] = fields["tier"]`, set once, never updated on subsequent merges — see
`write_block()`, which emits one `tier:` line for the whole merged block). A concept
assembled from a Tier-1 and a Tier-4 source today reports only the Tier-1 (or
whichever arrived first) tier for the entire block, losing the per-source distinction
`validator` and `article-synthesizer` would need to weight individual claims correctly.
This is the F6 finding from the #77 drift audit; fixing `dedup-extractions.py` is a
`scripts/` change out of this task's touched-file list.

What each stage does today, per this contract:
- `source-extractor` emits `tier: {1|2|3|4}` per concept block, one block per source
  (correct grain at emission).
- `dedup-extractions.py` **collapses** multiple source tiers into one first-seen value
  per merged slug (the gap above).
- `article-synthesizer` and `validator` consume whatever single tier value the merged
  block carries; neither currently has a way to recover per-source tier once merged.

## 4. Concept-block format (W1 extraction output)

Emitted by `source-extractor` to `dev/extractions/{batch_id}-concepts.md` (one file per
batch), consumed by `dedup-extractions.py` (W1b merge) and, per merged slug, written to
`dev/extractions/_dedup-{slug}.md` for `article-synthesizer`. Enforced by
`assert-structure.sh`'s `concept-batch`/`dedup-md` kind (both names alias the same
check: a `^## Concept:` header must exist).

```
## Concept: {title}

slug: {kebab-case-slug}
title: {human-readable title}
source_paths:
  - {path/to/source.md}
target_article: {existing-slug-if-updating | ""}
tier: {1|2|3|4}

### Claims

- {claim text} [source: {source-slug}, line ~{N}]
- {claim text} [source: {source-slug}]
```

A block starts at `## Concept:` and ends at the next `## Concept:` or end-of-file.
`source_paths:` is a YAML list (lines starting with `  - `). Multiple blocks with the
same `slug` across batches are merged by `dedup-extractions.py`: `source_paths` union
(first-seen order), `target_article` first non-empty wins, `title`/`tier` first-seen
wins (see Section 3 for why `tier` first-seen-wins is a known gap), `### Claims` lines
concatenated across all contributing blocks.

## Enforcement map

| `assert-structure.sh` kind | Checks |
|---|---|
| `concept-batch` / `dedup-md` | `^## Concept:` header present |
| `dedup-meta` | `ALL_SLUGS=` key present with a non-empty value |
| `article-md` | `^title:` and `^last_verified:` keys present |
| `audit-findings` | a `VALIDATED<TAB>` receipt row present (the validator wrote per-article receipts; `check-coverage.sh --verdict VALIDATED` does the per-slug reconciliation) |
| `enrichment-findings` | every non-blank line is an 8-tab-field row led by a `CANDIDATE\|WEAK\|DUP\|NOSOURCE` verdict |

A field in Section 1 or Section 4 with no row above is contract-required but not
machine-checked — drift there is caught only by review, not by the gate.
