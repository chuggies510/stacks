---
name: ingest-sources
description: |
  Use when the user wants to process new sources into topic guides for a
  knowledge stack. Detects new sources, classifies them into topic groups,
  extracts claims per group, and synthesizes topic guides. Must be run from
  within a library repo (one with catalog.md at root). Accepts an optional
  --from {path} argument to stage source files from an existing directory
  (e.g. migrating from another repo) before ingesting.
---

# Ingest

Process new sources into topic guides for a knowledge stack.

## Step 0: Telemetry

```bash
TELEMETRY_SH=$(find ~/.claude/plugins/cache -name telemetry.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
if [[ -z "$TELEMETRY_SH" ]]; then
  STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
  TELEMETRY_SH="$STACKS_ROOT/scripts/telemetry.sh"
fi
SKILL_NAME="stacks:ingest-sources" bash "$TELEMETRY_SH" 2>/dev/null || true
```

## Step 1: Gate check

Parse arguments. The full argument string is `$ARGUMENTS`. Extract stack name and optional `--from` path:

```bash
if [[ ! -f "catalog.md" ]]; then
  echo "ERROR: Not in a library repo (no catalog.md)."
  exit 1
fi

# Parse: /stacks:ingest-sources {stack} [--from {path}]
ARGS="$ARGUMENTS"
FROM_PATH=""
if [[ "$ARGS" == *"--from"* ]]; then
  STACK=$(echo "$ARGS" | sed 's/--from.*//' | tr -d '[:space:]')
  FROM_PATH=$(echo "$ARGS" | sed 's/.*--from[[:space:]]*//' | sed 's/[[:space:]]*$//')
  # Expand ~ if present
  FROM_PATH="${FROM_PATH/#\~/$HOME}"
else
  STACK="$ARGS"
fi

if [[ -z "$STACK" ]]; then
  echo "ERROR: Specify a stack name. Usage: /stacks:ingest-sources {stack-name} [--from {path}]"
  exit 1
fi
if [[ ! -f "$STACK/STACK.md" ]]; then
  echo "ERROR: Stack '$STACK' not found (no STACK.md). Run /stacks:new-stack $STACK first."
  exit 1
fi
if [[ -n "$FROM_PATH" ]] && [[ ! -d "$FROM_PATH" ]]; then
  echo "ERROR: --from path does not exist: $FROM_PATH"
  exit 1
fi
```

## Step 1.5: Stage sources from --from path (if provided)

If `$FROM_PATH` is set, copy readable source files into `$STACK/sources/incoming/` before detection runs. Only copy files Claude can read and extract knowledge from: markdown (`.md`, `.txt`) and text files. Skip binaries, PDFs, images, and other non-text formats — those require separate extraction tooling.

```bash
if [[ -n "$FROM_PATH" ]]; then
  echo "Staging sources from: $FROM_PATH"
  STAGED=0
  SKIPPED=0
  while IFS= read -r -d '' src_file; do
    filename=$(basename "$src_file")
    dest="$STACK/sources/incoming/$filename"
    # Handle filename collisions by appending a counter
    if [[ -f "$dest" ]]; then
      base="${filename%.*}"
      ext="${filename##*.}"
      counter=2
      while [[ -f "$STACK/sources/incoming/${base}-${counter}.${ext}" ]]; do
        ((counter++))
      done
      dest="$STACK/sources/incoming/${base}-${counter}.${ext}"
    fi
    cp "$src_file" "$dest"
    ((STAGED++))
  done < <(find "$FROM_PATH" -type f \( -name "*.md" -o -name "*.txt" \) -print0 2>/dev/null)

  # Count skipped (non-text files)
  TOTAL=$(find "$FROM_PATH" -type f ! -name ".gitkeep" 2>/dev/null | wc -l | tr -d ' ')
  SKIPPED=$((TOTAL - STAGED))

  echo "Staged $STAGED file(s) to $STACK/sources/incoming/"
  [[ $SKIPPED -gt 0 ]] && echo "Skipped $SKIPPED non-text file(s) (PDFs, images, binaries)"

  if [[ $STAGED -eq 0 ]]; then
    echo "ERROR: No readable source files found in $FROM_PATH"
    echo "Supported formats: .md, .txt"
    exit 1
  fi
fi
```

Report staging results to the user before proceeding. Tell them how many files were staged and which were skipped (and why).

## Step 2: Read schema

Read `$STACK/STACK.md` and extract:
- Source hierarchy (tier rankings for conflict resolution)
- Topic template (section structure for guides)
- Filing rules (how to organize sources by publisher/origin)
- Frontmatter convention (YAML fields expected in topic guides)

## Step 3: Detect new sources

List all files in `$STACK/sources/` (recursively, excluding .gitkeep and incoming/). Read `$STACK/index.md` Sources section. Sources listed in the index are already processed. New sources are files on disk not in the index.

```bash
# All source files currently on disk (excluding .gitkeep)
find "$STACK/sources" -type f ! -name ".gitkeep" | sort > /tmp/stacks-disk-sources.txt

# Extract source paths from index.md using a broader pattern
# Source entries look like: - [title](sources/path) — fall back to any sources/ reference
grep -o 'sources/[^)"]*' "$STACK/index.md" 2>/dev/null | \
  sed "s|^|$STACK/|" | sort > /tmp/stacks-indexed-sources.txt

# New = on disk but not in index
NEW_SOURCES=$(comm -23 /tmp/stacks-disk-sources.txt /tmp/stacks-indexed-sources.txt)
echo "New sources found: $(echo "$NEW_SOURCES" | grep -c . || echo 0)"
```

If no new sources, tell the user: "All sources already indexed. Nothing to ingest." and stop.

Note: source filenames with `(` or `)` characters are not supported by the index parser. Rename such files before ingesting.

Also check for sources in `$STACK/sources/incoming/` specifically — these are explicitly queued for processing. If any exist, they are always new.

## Step 4: Classify sources (Wave 0b)

Find the agents directory:
```bash
AGENTS_DIR=$(find ~/.claude/plugins/cache -type d -name "agents" -path "*/stacks/*" 2>/dev/null | sort -V | tail -1)
if [[ -z "$AGENTS_DIR" ]]; then
  STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
  AGENTS_DIR="$STACKS_ROOT/agents"
fi
```

```bash
# Locate wave-engine.md in the stacks plugin
WAVE_ENGINE=$(find ~/.claude/plugins/cache -name "wave-engine.md" -path "*/stacks/*/references/*" 2>/dev/null | sort -V | tail -1)
if [[ -z "$WAVE_ENGINE" ]]; then
  STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
  WAVE_ENGINE="$STACKS_ROOT/references/wave-engine.md"
fi
```

Read `$WAVE_ENGINE` for the topic-clusterer dispatch instructions.

If `$STACK/dev/curate/plan.md` already exists, dispatch topic-clusterer in refresh mode to classify new sources into existing groups or propose new ones.

If no plan exists (first ingest), dispatch topic-clusterer in full discovery mode to create the initial plan.

The topic-clusterer reads:
- The list of new sources (pass the file paths)
- `$STACK/STACK.md` (filing rules, source hierarchy)
- `$STACK/dev/curate/plan.md` (if exists, for refresh mode)

It writes `$STACK/dev/curate/plan.md` with source-to-topic-group assignments.

After the agent completes, read `$STACK/dev/curate/plan.md` and present the classification to the user. Ask for confirmation before proceeding:

"Here is how I've classified the new sources into topic groups:
{list groups with source counts}

Proceed with extraction? (yes/no/edit)"

If the user says edit, allow them to reassign sources to different groups or create new groups. Update the plan accordingly.

## Step 5: Wave 1 — Extract (parallel)

Read `$WAVE_ENGINE` for the topic-extractor dispatch instructions.

Create the extractions directory:
```bash
mkdir -p "$STACK/dev/curate/extractions"
```

For each topic group in `$STACK/dev/curate/plan.md` that has new sources, dispatch one topic-extractor agent. Dispatch all groups in parallel.

Instruct each topic-extractor agent: "Name each extraction file using the same normalization as the gate below: lowercase-hyphenated group name with special characters removed. For example, 'VAV Systems (Zone Control)' → `vav-systems-zone-control.md`."

Each agent:
- Reads source files assigned to its group
- Reads `$STACK/STACK.md` for source hierarchy and topic template
- Writes extractions to `$STACK/dev/curate/extractions/{topic-group}.md`

After all topic-extractor agents complete, verify the gate:

```bash
# Parse topic group names from plan.md
# Groups are section headings (## lines) in plan.md
GROUPS=$(grep '^## ' "$STACK/dev/curate/plan.md" | sed 's/^## //' | \
  sed 's/[^a-zA-Z0-9 -]//g' | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | sed 's/--*/-/g')
ALL_FOUND=true
for group in $GROUPS; do
  if [[ ! -f "$STACK/dev/curate/extractions/$group.md" ]]; then
    echo "Missing extraction: $group.md"
    ALL_FOUND=false
  fi
done
[[ "$ALL_FOUND" == true ]] || { echo "ERROR: Not all extractions completed. Check agent output."; exit 1; }
```

Note: topic-clusterer writes group names as `## Group Name` section headings in plan.md. The gate converts these to lowercase-hyphenated filenames (stripping non-alphanumeric characters) matching the extractor output convention.

## Step 6: Wave 2 — Synthesize (parallel)

Read `$WAVE_ENGINE` for the topic-synthesizer dispatch instructions.

For each topic group with extractions, dispatch one topic-synthesizer agent. Dispatch all groups in parallel.

Each agent:
- Reads `$STACK/dev/curate/extractions/{topic-group}.md`
- Reads `$STACK/STACK.md` for topic template and source hierarchy
- Reads existing `$STACK/topics/{topic}/guide.md` if it exists (update mode)
- Writes/updates `$STACK/topics/{topic}/guide.md`

Gate: wait for all guide files to exist before proceeding.

## Step 7: File sources

Move processed files from `$STACK/sources/incoming/` to their proper publisher directory based on STACK.md filing rules:

```bash
# Only move files that were processed (from incoming/)
INCOMING_FILES=$(find "$STACK/sources/incoming" -type f ! -name ".gitkeep" 2>/dev/null)
if [[ -n "$INCOMING_FILES" ]]; then
  echo "Filing sources from incoming/..."
fi
```

For each file in incoming/, determine the publisher directory from the filing rules in STACK.md. If the origin is unclear, ask the user which publisher directory to file under. Create the publisher directory if it doesn't exist.

## Step 8: Update index.md

Regenerate `$STACK/index.md` completely:

**Topics section**: scan `$STACK/topics/*/guide.md`, read frontmatter for title and source count:
```bash
find "$STACK/topics" -name "guide.md" | sort
```
For each guide, extract `title` and `sources` from YAML frontmatter.

If no guides exist yet, write the Topics section with a placeholder:
```markdown
## Topics

*No topics yet. Run `/stacks:ingest-sources {stack}` after adding sources.*
```

**Sources section**: scan all files in `$STACK/sources/` (all subdirs except incoming, excluding .gitkeep):
```bash
find "$STACK/sources" -type f ! -name ".gitkeep" | sort
```
List each with its relative path and parent directory (publisher).

Write the complete new index.md.

## Step 9: Update log.md

Prepend an entry to `$STACK/log.md`. Count from this run:
- N new sources processed (files that were in incoming/ or were new on disk)
- New topics created (guides that didn't exist before this run)
- Updated topics (guides that existed and were updated)
- Extraction count (files written to dev/curate/extractions/)

Set variables from counts gathered during the run, then write the entry:

```bash
NEW_ENTRY="## [$(date +%Y-%m-%d)] ingest | $N_SOURCES new sources processed
Processed $N_SOURCES files. $NEW_TOPICS new topics. $UPDATED_TOPICS updated. $EXTRACTION_COUNT extractions written."

{ printf '%s\n\n' "$NEW_ENTRY"; cat "$STACK/log.md"; } > /tmp/stacks-log.tmp
mv /tmp/stacks-log.tmp "$STACK/log.md"
```

## Step 10: Commit

```bash
git add "$STACK/"
git commit -m "feat($STACK): ingest {N} new sources, update topic guides"
```

Report summary to user:
- What was ingested (N sources)
- Which topics were created vs updated
- Suggest running `/stacks:refine-stack $STACK` next if 2+ guides exist
