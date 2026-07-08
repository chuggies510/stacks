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
| `sources` | YAML list of bare `sources/{publisher}/{file}.md` paths | `article-synthesizer` | `validator` (resolves each `[source-slug]` citation against this list); `/stacks:lookup` Step 7 (collects primary-source citations) | No (no grep kind checks list contents; `article-md` doesn't check this key) |
| `title` | string, human-readable | `article-synthesizer` | `assert-structure.sh` `article-md`; `/stacks:lookup` (cites articles by title) | Yes — key must exist |
| `routing` | one-line plain-text string, asker's-words description | `article-synthesizer` | `scripts/regenerate-moc.sh` (the MoC line per article); `/stacks:lookup` Step 6 (query-to-article recognition) | No |
| `tags` | YAML list, values drawn from `STACK.md`'s `allowed_tags:` | `article-synthesizer` | `scripts/regenerate-moc.sh` (groups the MoC by `tags[0]`); `scripts/normalize-tags.sh` (drift check against `allowed_tags:`) | No (no grep kind checks tag values; enforcement is `normalize-tags.sh`, not `assert-structure.sh`) |

`extraction_hash` and `updated` are **dead**: both were written but never read by any
current script or agent (grep across `scripts/`, `agents/`, `skills/` turns up only a
writer). `extraction_hash` came from a since-removed skip-list flywheel
(stacks#77/CHANGELOG); `updated` was dropped in stacks#90 for the same reason —
`last_verified` already carries article provenance. Both were stripped from the entire
corpus and must not be reintroduced. Verified empirically: `grep -rlnE
'extraction_hash|^updated:' */articles/*.md` across the library corpus returns zero files.

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

**Tier attaches per `source_path`, not per concept.** A concept block can merge claims
from sources of different tiers (e.g. a Tier-1 standard and a Tier-4 blog post both
discussing the same topic); each source keeps its own tier so claims trace back to it
for `article-synthesizer`'s STACK.md-hierarchy weighting (higher tier wins on conflict).

What each stage does (stacks#89 closed the F6 collapse):
- `source-extractor` emits `tier: {1|2|3|4}` per concept block, one block per source
  (correct grain at emission).
- `dedup-extractions.py` carries a `source_path → tier` map through the merge and emits
  the tier **inline per source** in the dedup block — `  - {path} (tier {N})` — with no
  collapsed block-level `tier:` scalar. A slug assembled from a Tier-1 and a Tier-4
  source keeps both distinctions (`slug_source_tier`, first-seen per source path).
- `article-synthesizer` reads each source's inline tier for hierarchy weighting, then
  writes the **bare** path (suffix stripped) into the article's `sources:` frontmatter —
  tier lives only in the extraction block, never in the article.
- `validator` recovers per-source tier at audit time from the STACK.md source hierarchy
  (it reads articles + sources + STACK.md, not the extraction block), so it needs no
  change from this seam.

## 4. Concept-block format (W1 extraction output)

Emitted by `source-extractor` to `dev/extractions/{batch_id}-concepts.md` (one file per
batch), consumed by `dedup-extractions.py` (W1b merge) and, per merged slug, written to
`dev/extractions/_dedup-{slug}.md` for `article-synthesizer`. Enforced by
`assert-structure.sh`'s `concept-batch`/`dedup-md` kind (both names alias the same
check: a `^## Concept:` header must exist).

**Source-extractor emission** (one block per source, so one `tier:`):

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

**Merged dedup block** (`dedup-extractions.py` output, one per unique slug): tier moves
inline onto each source and the block-level `tier:` scalar is gone (stacks#89, Section 3):

```
## Concept: {title}

slug: {kebab-case-slug}
title: {human-readable title}
source_paths:
  - {path/to/tier1-source.md} (tier 1)
  - {path/to/tier4-source.md} (tier 4)
target_article: {existing-slug-if-updating | ""}

### Claims

- {claim text} [source: {source-slug}]
```

**Receipted-empty sentinel** (`source-extractor`, pure-reference source, #93): a source
the extractor judges pure reference under STACK.md's discard test (CLI flag listings, API
reference pages, config-key catalogs) yields no concept blocks. Its `{batch_id}-concepts.md`
then contains ONLY a single line naming why:

```
# no-concepts: pure CLI flag reference, no behavior knowledge
```

`assert-structure.sh concept-batch` accepts this in place of a `## Concept:` block (the
reason after the colon must be non-empty). An empty or reason-less file still fails — a
missing batch file is far more often a real extractor failure than a genuine pure-reference
source. `dedup-extractions.py` ignores a sentinel-only file (no `## Concept:` header to
split on), so the source contributes zero slugs to W2 while still passing the W1 per-source
presence gate. Only the `concept-batch` kind accepts the sentinel; `dedup-md` (the merged
`_dedup.md`) does not — dedup never emits it.

A block starts at `## Concept:` and ends at the next `## Concept:` or end-of-file.
`source_paths:` is a YAML list (lines starting with `  - `). Multiple blocks with the
same `slug` across batches are merged by `dedup-extractions.py`: `source_paths` union
(first-seen order) each keeping its emitting block's tier inline, `target_article` first
non-empty wins, `title` first-seen wins, `### Claims` lines concatenated across all
contributing blocks.

## Enforcement map

| `assert-structure.sh` kind | Checks |
|---|---|
| `concept-batch` | `^## Concept:` header present, OR a lone `# no-concepts: <reason>` sentinel (non-empty reason) for a pure-reference source (#93) |
| `dedup-md` | `^## Concept:` header present (no sentinel — dedup never emits one) |
| `dedup-meta` | `ALL_SLUGS=` key present with a non-empty value |
| `article-md` | `^title:` and `^last_verified:` keys present |
| `audit-findings` | a `VALIDATED<TAB>` receipt row present (the validator wrote per-article receipts; `check-coverage.sh --verdict VALIDATED` does the per-slug reconciliation) |
| `enrichment-findings` | every non-blank line is an 8-tab-field row led by a `CANDIDATE\|WEAK\|DUP\|NOSOURCE` verdict |

A field in Section 1 or Section 4 with no row above is contract-required but not
machine-checked — drift there is caught only by review, not by the gate.
