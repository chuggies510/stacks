# Refresh Procedure — Incremental Knowledge Synthesis

Triggered by `/stacks:ingest refresh`. Detects new/changed sources and selectively re-runs affected waves.

## Step 1: Detect Changes

Diff `sources/` directory listing against the Sources section of `index.md`:

```bash
# List files in sources/ (sorted)
ls {stack}/sources/ | sort > /tmp/sources-actual.txt

# Extract source filenames from index.md Sources section
grep -E '^\- |^  - ' {stack}/index.md | sed 's/.*sources\///' | sed 's/[) ].*//' | sort > /tmp/sources-indexed.txt

# New sources = in actual but not indexed
comm -23 /tmp/sources-actual.txt /tmp/sources-indexed.txt > /tmp/new-sources.txt
cat /tmp/new-sources.txt
```

If diff is empty: "All sources indexed. Nothing to refresh." Stop.
If diff is non-empty: proceed with changed file list.

## Step 2: Classify Changes

Dispatch `topic-clusterer` agent in refresh mode:

```
Prompt: "Classify these new/changed sources into topic groups.

New sources:
{list of new source filenames from diff}

Existing plan: dev/curate/plan.md
Source hierarchy and template: STACK.md

For each source: assign to an existing topic group or propose a new one.
Write classification to: dev/curate/refresh-classification.md
Project root: {pwd}"
```

Present classification to user via AskUserQuestion for confirmation.

## Step 3: Selective Re-run

Based on confirmed classification:

- **New topic groups**: Full Wave 1 + Wave 2 for those groups
- **Existing groups with new sources**: Full Wave 1 re-extraction (all sources in group, not just new) + Wave 2 re-synthesis
- **Wave 3**: Always re-run (cross-reference needs full picture)
- **Waves 4–6**: Always re-run (validation, synthesis, and findings need full picture)

Use the same agent dispatch prompts from wave-engine.md, scoped to affected groups only.

## Step 4: Update State

- Update `Last Synthesized` date in dev/curate/plan.md
- Update Source Inventory file counts
- Add new topic group rows if created
- Update source lists for affected groups
- Reset wave statuses for re-run waves, then mark complete as they finish
