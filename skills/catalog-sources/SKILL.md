---
name: catalog-sources
description: |
  Use when the user wants to process new sources into article-per-concept wiki
  entries for a knowledge stack. Enumerates new sources, identifies concepts per
  source (W1), deduplicates shared concept slugs (W1b), synthesizes one article
  per unique concept (W2), files sources to their publisher directory (W3), and
  regenerates the stack Map of Contents (W4). Must be run from within a library
  repo (one with catalog.md at root). Accepts an optional --from {path} argument
  to stage source files from an existing directory before cataloging.
---

# Catalog Sources

Process new sources into article-per-concept wiki entries for a knowledge stack.

## Step 0: Telemetry

```bash
STACKS_ROOT="$CLAUDE_PLUGIN_ROOT"
SKILL_NAME="stacks:catalog-sources" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
```

## Step 1: Gate check

Parse arguments. The full argument string is `$ARGUMENTS`. Extract optional stack name and optional `--from` path:

```bash
if [[ ! -f "catalog.md" ]]; then
  echo "ERROR: Not in a library repo (no catalog.md)."
  exit 1
fi

# Parse: /stacks:catalog-sources [{stack}] [--from {path}]
ARGS="$ARGUMENTS"
FROM_PATH=""
if [[ "$ARGS" == *"--from"* ]]; then
  STACK=$(echo "$ARGS" | sed 's/--from.*//' | tr -d '[:space:]')
  FROM_PATH=$(echo "$ARGS" | sed 's/.*--from[[:space:]]*//' | sed 's/[[:space:]]*$//')
  FROM_PATH="${FROM_PATH/#\~/$HOME}"
else
  STACK=$(echo "$ARGS" | tr -d '[:space:]')
fi

if [[ -n "$FROM_PATH" ]] && [[ ! -d "$FROM_PATH" ]]; then
  echo "ERROR: --from path does not exist: $FROM_PATH"
  exit 1
fi

# Auto-pick target stack(s) when none specified.
# Rule: no argument = catalog every stack with incoming/ files, largest batch first.
# Explicit stack argument still wins (needed for --from, or forcing a no-incoming
# re-catalog after manual edits to sources/).
if [[ -z "$STACK" ]]; then
  if [[ -n "$FROM_PATH" ]]; then
    echo "ERROR: --from requires an explicit stack name."
    exit 1
  fi
  STACK_QUEUE=$(for d in */STACK.md; do
    name=$(dirname "$d")
    count=$(find "$name/sources/incoming" -type f ! -name ".gitkeep" 2>/dev/null | wc -l | tr -d ' ')
    [[ "$count" -gt 0 ]] && echo "$count $name"
  done | sort -rn | awk '{print $2}')
  if [[ -z "$STACK_QUEUE" ]]; then
    echo "No stacks have queued sources in incoming/. Nothing to catalog."
    exit 0
  fi
  echo "Auto-cataloging stacks with queued sources (largest first):"
  for s in $STACK_QUEUE; do
    echo "  $s ($(find "$s/sources/incoming" -type f ! -name ".gitkeep" 2>/dev/null | wc -l | tr -d ' ') files)"
  done
  # Run steps 2-11 once per stack in STACK_QUEUE. Continue on per-stack failures
  # so one broken source doesn't block the rest.
else
  if [[ ! -f "$STACK/STACK.md" ]]; then
    echo "ERROR: Stack '$STACK' not found (no STACK.md). Run /stacks:new-stack $STACK first."
    exit 1
  fi
  STACK_QUEUE="$STACK"
fi
```

For the remainder of the skill (Steps 2-10), when `STACK_QUEUE` contains multiple stacks, treat each stack as an independent cataloging run: iterate through them sequentially, performing all steps for one stack before moving to the next. Commit per stack (Step 10) so a failure mid-queue still leaves prior stacks in a clean state.

## Step 1.5: Stage sources from --from path (if provided)

If `$FROM_PATH` is set, copy candidate source files into `$STACK/sources/incoming/` before detection runs. Stage text AND document formats (`.md/.txt/.html`, `.pdf`, `.docx/.doc/.odt/.rtf`, `.xlsx/.xls/.ods`, `.ppt/.pptx`); the convert stage (Step 3.5) turns the documents into readable text and skips-and-reports anything it can't (images, scanned PDFs, unknown binaries). Type-awareness lives in one place — the converter — not split between here, the converter, and `process-inbox`.

```bash
if [[ -n "$FROM_PATH" ]]; then
  echo "Staging sources from: $FROM_PATH"
  STAGED=0
  while IFS= read -r -d '' src_file; do
    filename=$(basename "$src_file")
    dest=$(bash "$STACKS_ROOT/scripts/collision-dest.sh" "$STACK/sources/incoming" "$filename")
    cp "$src_file" "$dest"
    ((STAGED++))
  done < <(find "$FROM_PATH" -type f \( \
      -iname "*.md" -o -iname "*.txt" -o -iname "*.html" -o -iname "*.htm" \
      -o -iname "*.pdf" -o -iname "*.docx" -o -iname "*.doc" -o -iname "*.odt" -o -iname "*.rtf" \
      -o -iname "*.xlsx" -o -iname "*.xls" -o -iname "*.ods" -o -iname "*.pptx" -o -iname "*.ppt" \
    \) -print0 2>/dev/null)

  TOTAL=$(find "$FROM_PATH" -type f ! -name ".gitkeep" 2>/dev/null | wc -l | tr -d ' ')
  SKIPPED=$((TOTAL - STAGED))

  echo "Staged $STAGED file(s) to $STACK/sources/incoming/"
  [[ $SKIPPED -gt 0 ]] && echo "Skipped $SKIPPED non-source file(s) (images, unknown binaries)"

  if [[ $STAGED -eq 0 ]]; then
    echo "ERROR: No source files found in $FROM_PATH"
    echo "Supported: .md .txt .html, .pdf, .docx/.doc/.odt/.rtf, .xlsx/.xls/.ods, .pptx/.ppt"
    exit 1
  fi
fi
```

Report staging results to the user before proceeding. Tell them how many files were staged and which were skipped (and why).

## Step 2: Read STACK.md

Read `$STACK/STACK.md` and extract:
- Source hierarchy (tier rankings for conflict resolution)
- Scope (what topics belong in this stack)
- Filing rules (how to organize sources by publisher/origin)
- Frontmatter convention (YAML fields expected in articles)

## Step 3: Locate plugin scripts and agents

Derive sibling paths from `STACKS_ROOT` (set in Step 0 via the shared resolver):

```bash
SCRIPTS_DIR="$STACKS_ROOT/scripts"
AGENTS_DIR="$STACKS_ROOT/agents"
```

Each fan-out wave (W1, W2) gates its agents' output with `gate-batch.sh`: the parent captures a dispatch epoch before dispatch, and after fan-in every expected file must be non-empty and newer than that epoch (a write-or-fail check), plus a content-shape check via `assert-structure.sh`.

## Step 3.5: Convert non-text sources to readable text

`sources/incoming/` may hold documents the extractor agent cannot read with `Read` — PDFs (page-capped, truncate silently), Office binaries (zipped XML, garble), images. Convert them to text sidecars BEFORE enumeration so the agent always receives readable text it can consume in full. This runs per-stack (direct drops into any stack's `incoming/`, not just `--from` staging).

```bash
bash "$SCRIPTS_DIR/convert-sources.sh" "$STACK/sources/incoming" "$STACK/sources/.raw"
```

The converter (single source of type-awareness): text passes through; PDF → `pdfplumber` text sidecar (full document, no page cap; multi-column layout preserved); `.docx` → `pandoc`; spreadsheets/slides/legacy Office → `libreoffice` headless. Each converted original is moved to `sources/.raw/` (gitignored — provenance kept out of the library's article history). Images, scanned PDFs (no text layer), and unknown binaries are skipped and listed, never garbled. **Surface the converter's report to the operator** so any skipped source is visible — a knowledge base built on silently-incomplete extraction reads as authoritative while being wrong.

After this step `incoming/` holds only readable text; W0 enumerates that.

## Step 4: W0 — Enumerate new sources

Files in `sources/incoming/` are by definition not yet filed or indexed (W3 moves them after successful catalog); they ARE the new-source set. No diff against `index.md` is needed here.

```bash
NEW_SOURCES=$(find "$STACK/sources/incoming" -type f ! -name ".gitkeep" | sort)
echo "New sources found: $(echo "$NEW_SOURCES" | grep -c . || echo 0)"
```

Gate: source filenames with `(` or `)` characters break the index parser. Fail early if any exist:

```bash
PAREN_FILES=$(find "$STACK/sources/incoming" -type f \( -name '*(*' -o -name '*)*' \) ! -name ".gitkeep" 2>/dev/null)
if [[ -n "$PAREN_FILES" ]]; then
  echo "ERROR: Source filenames contain '(' or ')' which breaks the index parser:"
  echo "$PAREN_FILES"
  echo "Rename these files before cataloging (e.g., replace '(foo)' with '-foo')."
  exit 1
fi
```

If `NEW_SOURCES` is empty, tell the user: "All sources already indexed. Nothing to catalog." and stop.

## Step 6: W1 — Parent-side parallel source-extractor dispatch

The parent skill (this session) shards sources directly and dispatches `source-extractor` agents in parallel. The `source-extractor-orchestrator` agent is **deprecated for this skill**: same root cause as the audit-stack orchestrators. Nested Task dispatch was unreliable and the orchestrator silently fell back to inline execution, defeating the sharding. Parent-side dispatch keeps Task usage shallow and lets the parent run the deterministic W1b merge in code.

**Batch size: 1 source per source-extractor agent.** Per-source isolation matters more than minimizing dispatch count. Each agent reads one source plus the existing `articles/` listing (for slug-immutability checks) and writes one `dev/extractions/batch-{NN}-concepts.md` file. Bundling multiple sources into one agent invites concept-bleed across sources — claims from source A get attributed to a concept first identified in source B.

```bash
NEW_SOURCES_ARR=()
while IFS= read -r src; do
  [[ -z "$src" ]] && continue
  NEW_SOURCES_ARR+=("$src")
done <<< "$NEW_SOURCES"
N_SOURCES=${#NEW_SOURCES_ARR[@]}
if (( N_SOURCES == 0 )); then
  echo "W1: no new sources. Nothing to catalog."
  return 0 2>/dev/null || exit 0
fi
N_BATCHES_W1=$N_SOURCES
mkdir -p "$STACK/dev/extractions"
rm -f "$STACK/dev/extractions"/batch-*-concepts.md
rm -f "$STACK/dev/extractions"/_dedup*.md
DISPATCH_EPOCH_W1=$(date +%s)
```

**Dispatch:** in a single message, emit one `Agent` tool call per source (subagent_type `stacks:source-extractor`). Each prompt names: the assigned `batch_id` (`batch-1`, `batch-2`, …), the absolute source path, the path to `$STACK/STACK.md`, and the existing `$STACK/articles/` listing. Tell each agent to write its output to `dev/extractions/{batch_id}-concepts.md`. Parallel dispatch is mandatory.

**Gate W1:**

```bash
W1_PATHS=()
for ((i=1; i<=N_BATCHES_W1; i++)); do
  W1_PATHS+=("$STACK/dev/extractions/batch-${i}-concepts.md")
done
bash "$SCRIPTS_DIR/gate-batch.sh" "$DISPATCH_EPOCH_W1" "source-extractor" concept-batch "${W1_PATHS[@]}"
```

## Step 6.5: W1b — Deterministic dedup in the parent

Group concept blocks across all W1 outputs by slug. For any slug appearing in multiple batches, merge `source_paths[]` into a single unified block. Classify each unique slug as `new` (no `target_article` in any contributing block) or `updated`. All deterministic; no agent needed.

A concept block in `batch-{N}-concepts.md` looks like:

```
## Concept: {title}

slug: {kebab-case-slug}
title: {human title}
source_paths:
  - {path}
target_article: {existing-slug | ""}
tier: {1|2|3|4}

### Claims
- ...
```

Block boundaries: a block starts at `## Concept:` and ends at the next `## Concept:` or end-of-file. Within a block, `source_paths:` is a YAML list (lines starting with `  - `).

```bash
DEDUP="$STACK/dev/extractions/_dedup.md"
: > "$DEDUP"

# Pass 1: aggregate every concept block from every batch into a flat working
# stream, keyed by slug. For each unique slug, merge source_paths (union,
# preserving first-seen order across all contributing blocks) and remember
# whether any contributing block had a non-empty target_article.
python3 "$SCRIPTS_DIR/dedup-extractions.py" "$STACK/dev/extractions" "$DEDUP"
"$SCRIPTS_DIR/assert-structure.sh" "$DEDUP" dedup-md "dedup-extractions" \
  || { echo "STRUCTURE_FAILURE: dedup output malformed — no concept blocks"; exit 1; }
"$SCRIPTS_DIR/assert-structure.sh" "$STACK/dev/extractions/_dedup-meta.txt" dedup-meta "dedup-extractions" \
  || { echo "STRUCTURE_FAILURE: dedup meta malformed — missing or empty ALL_SLUGS"; exit 1; }

# Load the meta into shell vars (ALL_SLUGS, UPDATED_SLUGS, N_NEW, N_UPDATED,
# N_UNIQUE_CONCEPTS, INPUT_BLOCKS — used by W2 dispatch and the Step 10 commit).
source <(grep -E '^[A-Z_]+=' "$STACK/dev/extractions/_dedup-meta.txt" | sed 's/^/export /')
CONCEPT_SLUGS=($ALL_SLUGS)
```

The Python pass merges `source_paths[]` deterministically (set-of-seen with first-seen-order preservation) and writes a single canonical `_dedup.md` plus one `_dedup-{slug}.md` per unique slug.

## Step 6.75: W2 — Parent-side parallel article-synthesizer dispatch

Article-synthesizer is naturally 1-per-slug — each agent reads one `_dedup-{slug}.md` and writes one `articles/{slug}.md`. No batching needed.

**Wave cap: 25 agents per dispatch wave.** This matches the prior orchestrator's `W2_WAVE_CAP` to avoid overwhelming the harness on stacks with hundreds of new concepts. Each wave runs in parallel; waves run sequentially. Each wave captures its own dispatch epoch so the gate compares each wave's articles against the epoch immediately preceding their dispatch.

Each wave does, in order: (1) capture a dispatch epoch then dispatch one `stacks:article-synthesizer` per slug in a single message; (2) gate every expected article against that wave's epoch.

```bash
W2_WAVE_CAP=25
W2_FAILED=()
n=${#CONCEPT_SLUGS[@]}
i=0
while (( i < n )); do
  WAVE_SLICE=("${CONCEPT_SLUGS[@]:i:W2_WAVE_CAP}")

  # 1. Capture this wave's dispatch epoch, then dispatch.
  DISPATCH_EPOCH_W2_WAVE=$(date +%s)
  # In a single message, dispatch one stacks:article-synthesizer agent per slug
  # in WAVE_SLICE. Each prompt names:
  #   - $STACK/dev/extractions/_dedup-${slug}.md (concept block, self-contained)
  #   - $STACK/articles/${slug}.md if slug is in UPDATED_SLUGS (else absent)
  #   - $STACK/STACK.md (for source hierarchy + allowed_tags)
  # ----- DISPATCH MARKER (parent does this) -----

  # 2. After fan-in, gate each article in this wave against this wave's epoch.
  WAVE_ARTICLE_PATHS=()
  for slug in "${WAVE_SLICE[@]}"; do
    WAVE_ARTICLE_PATHS+=("$STACK/articles/${slug}.md")
  done
  if ! bash "$SCRIPTS_DIR/gate-batch.sh" "$DISPATCH_EPOCH_W2_WAVE" "article-synthesizer" article-md "${WAVE_ARTICLE_PATHS[@]}"; then
    W2_FAILED+=("${WAVE_ARTICLE_PATHS[@]}")
  fi
  ((i += W2_WAVE_CAP))
done
if (( ${#W2_FAILED[@]} > 0 )); then
  exit 1
fi
```

The counts needed for the Step 10 commit (`N_SOURCES`, `N_NEW`, `N_UPDATED`) are already in shell vars (`N_SOURCES` from W1; `N_NEW`/`N_UPDATED` sourced from the dedup meta at W1b). Clean up the working meta file:

```bash
rm -f "$STACK/dev/extractions/_dedup-meta.txt"
```

Downstream steps (tag drift check, W3 source filing, W4 MoC update) remain in this skill after Step 6.75 succeeds.

## Step 7: Tag drift check

After W2, enforce the tag vocabulary declared in `STACK.md`. The check reads `allowed_tags:` from the stack root and halts the pipeline if any article carries an out-of-vocabulary tag. No auto-rewrite — drift is a surfaced defect the operator resolves by editing either the offending article or the vocabulary list.

```bash
"$SCRIPTS_DIR/normalize-tags.sh" "$STACK"
```

On non-zero exit, halt the catalog pipeline and surface the `TAG_DRIFT:` stderr lines to the user. Do not proceed to W3 (source filing) — sources for drifted articles stay in `incoming/` so the next run retries after the operator fixes the tags. When `allowed_tags:` is absent or empty, the script emits a `normalize-tags: allowed_tags not declared, skipping drift check` warning to stderr and exits 0 (backward-compat for stacks that haven't migrated).

## Step 8: W3 — Source filing

Move successfully synthesized source files from `sources/incoming/` to their publisher directory. Only move sources for which all expected articles passed their W2 write gates. Failed articles block their sources' filing at W3 below.

```bash
INCOMING_FILES=$(find "$STACK/sources/incoming" -type f ! -name ".gitkeep" 2>/dev/null)
if [[ -n "$INCOMING_FILES" ]]; then
  echo "W3: filing sources from incoming/ to sources/{publisher}/..."
fi
```

For each file in `incoming/`, determine the publisher directory from the filing rules in `STACK.md`. If the origin is unclear from filename and frontmatter, ask the user which publisher directory to file under. Create the publisher directory if it does not exist:

```bash
# For each source file that had at least one successfully written article:
publisher=$(grep -m1 '^publisher:' "$src_file" 2>/dev/null | awk '{print $2}')
# Fallback: infer publisher from filename prefix or ask user
pub="${publisher:-unknown}"
dest_dir="$STACK/sources/$pub"
mkdir -p "$dest_dir"
fname=$(basename "$src_file")
mv "$src_file" "$dest_dir/"
# W1/W2 cited this source at sources/incoming/$fname (its location then); the mv
# orphans that ref. Rewrite incoming→publisher across articles in the same pass.
"$SCRIPTS_DIR/rewrite-source-refs.sh" "$STACK/articles" "$fname" "$pub"
```

Partial failure is acceptable: unmoved sources remain in `incoming/` and are picked up on the next `/stacks:catalog-sources` run. Sources for failed concepts stay in `incoming/` and are picked up on the next run. No rollback.

## Step 9: W4 — MoC update

Regenerate `$STACK/index.md` from article frontmatter. The generator reads the existing `index.md`, preserves any `## Reading Paths` section verbatim, and rewrites all other sections.

```bash
"$SCRIPTS_DIR/regenerate-moc.sh" "$STACK"
```

The `## Reading Paths` section is preserved verbatim. Any user-curated reading path content in that section survives across catalog runs unchanged. All other sections (title, generated article groupings by `tags[0]`) are rewritten.

## Step 10: Log + commit

Prepend an entry to `$STACK/log.md`:

Use the counts already in shell vars: `N_SOURCES` (W1), and `N_NEW` / `N_UPDATED` (sourced from the dedup meta at W1b).

```bash
NEW_ENTRY="## [$(date +%Y-%m-%d)] catalog | $N_SOURCES new sources, $N_NEW articles created, $N_UPDATED articles updated
Sources processed: $N_SOURCES. New articles: $N_NEW. Updated articles: $N_UPDATED."

{ printf '%s\n\n' "$NEW_ENTRY"; cat "$STACK/log.md"; } > /tmp/stacks-log.tmp
mv /tmp/stacks-log.tmp "$STACK/log.md"
```

Commit the stack:

```bash
git add "$STACK/"
git commit -m "feat($STACK): catalog $N_SOURCES sources, $N_NEW new articles, $N_UPDATED updated"
```

Report summary to the user:
- How many sources were processed
- How many articles were created vs updated
- Whether any sources remain in `incoming/` (failed W2 gates) and what to do about them
- Suggest running `/stacks:audit-stack $STACK` next if 2+ articles exist
