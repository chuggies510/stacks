# Wave Engine — Knowledge Synthesis

Unified execution engine for Build Mode (all waves) and Refresh Mode (affected waves only).

## Wave Definitions

| Wave | Type | Agent(s) | Parallelism | Input | Output |
|------|------|----------|-------------|-------|--------|
| 0 | Enumerate | Diff sources/ vs index.md | Single | sources/, index.md | List of new sources |
| 0b | Cluster | topic-clusterer | Single | new sources list | dev/curate/plan.md |
| 1 | Extract | topic-extractor | Parallel per topic | Source markdowns per group | dev/curate/extractions/{topic}.md |
| 2 | Synthesize | topic-synthesizer | Parallel per topic | Extraction per group | topics/{topic}/guide.md |
| 3 | Cross-reference | cross-referencer | Single | All topic guides | dev/curate/cross-reference-report.md |
| 4 | Validate | validator | Single | All guides + sources | dev/curate/validation-report.md |
| 5 | Synthesize cross-cutting | synthesizer | Single | All guides | dev/curate/glossary.md, dev/curate/invariants.md |
| 6 | Findings | findings-analyst | Single | All guides + reports | dev/curate/findings.md |

Waves 3–6 are dispatched by `/stacks:refine`. Waves 0–2 are dispatched by `/stacks:ingest`.

**Dependency rule**: Each wave gates on the prior wave completing. If any Wave N output is refreshed, Waves N+1 through 6 re-run.

## Execution

### Wave 0 — Source Detection

Diff `sources/` directory listing against the Sources section of `index.md` to find new sources:

```bash
# List files in sources/ (sorted)
ls {stack}/sources/ | sort > /tmp/sources-actual.txt

# Extract source filenames from index.md Sources section
grep -E '^\- |^  - ' {stack}/index.md | sed 's/.*sources\///' | sed 's/[) ].*//' | sort > /tmp/sources-indexed.txt

# New sources = in actual but not indexed
comm -23 /tmp/sources-actual.txt /tmp/sources-indexed.txt
```

**Gate**: If diff is empty, "All sources indexed. Nothing to do." Stop.

### Wave 0b — Topic Clustering

Dispatch `topic-clusterer` agent:

```
Prompt: "Cluster the sources listed in index.md (Sources section) into topic groups.

For each source, read the title and scan the first 50 lines to understand the subject.
Group by system served, not engineering concept. Minimum 2 sources per group.

Read existing dev/curate/plan.md if it exists (refresh mode) or create new (build mode).
Template sections and source hierarchy are in STACK.md.

Write plan to: dev/curate/plan.md
Project root: {pwd}"
```

**Gate**: `dev/curate/plan.md` exists with at least 1 topic group row.
**User gate**: Present topic groups via AskUserQuestion for confirmation before proceeding.

### Wave 1 — Extraction

For each topic group in dev/curate/plan.md, dispatch one `topic-extractor` agent **in parallel**:

```
Prompt: "Extract knowledge for the '{topic_name}' topic group.

Source files to read:
{list of source markdown paths from plan.md row}

Template sections and source hierarchy are in STACK.md.

Write extraction to: dev/curate/extractions/{topic_slug}.md
Project root: {pwd}"
```

**Gate**: All `dev/curate/extractions/{topic}.md` files exist (one per topic group).
Update dev/curate/plan.md: Wave 1 status → complete.

### Wave 2 — Synthesis

For each topic group, dispatch one `topic-synthesizer` agent **in parallel**:

```
Prompt: "Synthesize the '{topic_name}' topic guide.

Extraction file: dev/curate/extractions/{topic_slug}.md

Template sections and source hierarchy are in STACK.md.

Write topic guide to: topics/{topic_slug}/guide.md
Create the directory if it doesn't exist.
Project root: {pwd}"
```

**Gate**: All `topics/{topic}/guide.md` files exist (one per topic group).
Update dev/curate/plan.md: Wave 2 status → complete.

### Wave 3 — Cross-Reference

Dispatch single `cross-referencer` agent:

```
Prompt: "Cross-reference all synthesized topic guides for consistency.

Topic guides to read:
{list all topics/*/guide.md paths}

Write cross-reference report to: dev/curate/cross-reference-report.md
Project root: {pwd}"
```

**Gate**: `dev/curate/cross-reference-report.md` exists.
Update dev/curate/plan.md: Wave 3 status → complete.

### Wave 4 — Validation

Dispatch single `validator` agent:

```
Prompt: "Validate topic guide claims against source files.

Topic guides: {list all topics/*/guide.md paths}
Source files: {list all sources/* paths}
Source hierarchy: STACK.md

Write validation report to: dev/curate/validation-report.md
Project root: {pwd}"
```

**Gate**: `dev/curate/validation-report.md` exists.
Update dev/curate/plan.md: Wave 4 status → complete.

### Wave 5 — Cross-Cutting Synthesis

Dispatch single `synthesizer` agent:

```
Prompt: "Synthesize cross-cutting artifacts from all topic guides.

Topic guides: {list all topics/*/guide.md paths}
Source hierarchy: STACK.md

Write glossary to: dev/curate/glossary.md
Write invariants to: dev/curate/invariants.md
Project root: {pwd}"
```

**Gate**: `dev/curate/glossary.md` and `dev/curate/invariants.md` exist.
Update dev/curate/plan.md: Wave 5 status → complete.

### Wave 6 — Findings

Dispatch single `findings-analyst` agent:

```
Prompt: "Analyze knowledge stack quality and produce findings.

Topic guides: {list all topics/*/guide.md paths}
Cross-reference report: dev/curate/cross-reference-report.md
Validation report: dev/curate/validation-report.md
Source hierarchy and template: STACK.md

Write findings to: dev/curate/findings.md
Project root: {pwd}"
```

**Gate**: `dev/curate/findings.md` exists.
Update dev/curate/plan.md: Wave 6 status → complete, Last Synthesized → today's date, Status → complete.

## Error Handling

If an agent fails (no output file produced):
1. Mark wave status as "failed" in dev/curate/plan.md
2. Report which topic group / agent failed
3. Do not proceed to next wave
4. User can re-run `/stacks:ingest` or `/stacks:refine` to retry from failed wave
