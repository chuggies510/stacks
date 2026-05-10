---
name: catalog-sources
description: |
  Use when the user wants to process new sources into article-per-concept wiki
  entries for a knowledge stack. Enumerates new sources, reads prior audit
  findings to build a skip list, identifies concepts per source (W1), deduplicates
  shared concept slugs (W1b), synthesizes one article per unique concept (W2),
  runs a wikilink pass (W2b), files sources to their publisher directory (W3),
  and regenerates the stack Map of Contents (W4). Must be run from within a
  library repo (one with catalog.md at root). Accepts an optional --from {path}
  argument to stage source files from an existing directory before cataloging.
---

# Catalog Sources

Process new sources into article-per-concept wiki entries for a knowledge stack.

## Step 0: Telemetry

```bash
LOCATE=$(find ~/.claude/plugins/cache -name locate-plugin-root.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
[[ -z "$LOCATE" ]] && LOCATE="$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)/scripts/locate-plugin-root.sh"
STACKS_ROOT=$(bash "$LOCATE" 2>/dev/null)
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
    n=$(find "$s/sources/incoming" -type f ! -name ".gitkeep" | wc -l | tr -d ' ')
    echo "  $s ($n files)"
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

If `$FROM_PATH` is set, copy readable source files into `$STACK/sources/incoming/` before detection runs. Only copy files Claude can read and extract knowledge from: markdown (`.md`, `.txt`) and text files. Skip binaries, PDFs, images, and other non-text formats.

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
WAVE_ENGINE="$STACKS_ROOT/references/wave-engine.md"
```

Read `$WAVE_ENGINE` for canonical wave descriptions and `assert-written.sh` usage examples.

## Step 4: W0 — Enumerate new sources

Files in `sources/incoming/` are by definition not yet filed or indexed (W3 moves them after successful catalog); they ARE the new-source set. No diff against `index.md` is needed here. Deduplication of already-synthesized content is handled at W0b by the extraction-hash skip list.

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

## Step 5: W0b — Prior-findings gate

Read `$STACK/dev/audit/findings.md` if it exists. Extract `extraction_hash` values from all items with a terminal status (`applied`, `closed`). These hashes represent content already synthesized; concept-identifier will skip them.

```bash
SKIP_HASHES=""
FINDINGS="$STACK/dev/audit/findings.md"
if [[ -f "$FINDINGS" ]]; then
  # Extract extraction_hash values from terminal-status items
  # Items have YAML-style fields; terminal statuses: applied, closed
  # Item boundary is `- id:`, not blank line. Blank-line-as-terminator misses
  # items abutting without separator and bleeds prior status into the next.
  SKIP_HASHES=$(awk '
    function flush() {
      if (have && (status=="applied" || status=="closed") && hash != "") print hash
      have=0; hash=""; status=""
    }
    /^- id:/ { flush(); have=1; next }
    have && /extraction_hash:/ { hash=$2 }
    have && /status:/ { status=$2 }
    END { flush() }
  ' "$FINDINGS")
  SKIP_COUNT=$(echo "$SKIP_HASHES" | grep -c . || echo 0)
  echo "W0b: loaded $SKIP_COUNT extraction_hash values to skip (terminal-status findings)"
else
  echo "W0b: no prior findings.md; skip list is empty (first catalog run)"
fi
```

Missing `findings.md` is a no-op; skip list is empty on the first run.

## Step 6: W1 — Parent-side parallel concept-identifier dispatch

The parent skill (this session) shards sources directly and dispatches `concept-identifier` agents in parallel. The `concept-identifier-orchestrator` agent is **deprecated for this skill**: same root cause as the audit-stack orchestrators. Nested Task dispatch was unreliable and the orchestrator silently fell back to inline execution, defeating the sharding. Parent-side dispatch keeps Task usage shallow and lets the parent run the deterministic W1b merge in code.

**Batch size: 1 source per concept-identifier agent.** Per-source isolation matters more than minimizing dispatch count. Each agent reads one source plus the existing `articles/` listing (for slug-immutability checks) and writes one `dev/extractions/batch-{NN}-concepts.md` file. Bundling multiple sources into one agent invites concept-bleed across sources — claims from source A get attributed to a concept first identified in source B.

```bash
NEW_SOURCES_ARR=()
while IFS= read -r src; do
  [[ -z "$src" ]] && continue
  NEW_SOURCES_ARR+=("$src")
done <<< "$NEW_SOURCES"
N_SOURCES=${#NEW_SOURCES_ARR[@]}
if (( N_SOURCES == 0 )); then
  echo "W1: no new sources. Writing zero-count summary and exiting."
  mkdir -p "$STACK/dev/extractions"
  jq -n '{schema_version:1, wave:"w1-w2", status:"ok",
          counts:{n_sources:0, n_batches_w1:0, n_concepts_input:0,
                  n_unique_concepts:0, n_articles_new:0, n_articles_updated:0,
                  n_w2_waves:0},
          epochs:{}}' \
    > "$STACK/dev/extractions/_w1-w2-summary.json"
  return 0 2>/dev/null || exit 0
fi
N_BATCHES_W1=$N_SOURCES
mkdir -p "$STACK/dev/extractions"
rm -f "$STACK/dev/extractions"/batch-*-concepts.md
rm -f "$STACK/dev/extractions"/_dedup*.md
DISPATCH_EPOCH_W1=$(date +%s)
```

**Dispatch:** in a single message, emit one `Agent` tool call per source (subagent_type `stacks:concept-identifier`). Each prompt names: the assigned `batch_id` (`batch-1`, `batch-2`, …), the absolute source path, the path to `$STACK/STACK.md`, the existing `$STACK/articles/` listing, and the `$SKIP_HASHES` list. Tell each agent to write its output to `dev/extractions/{batch_id}-concepts.md`. Parallel dispatch is mandatory.

**Gate W1:**

```bash
W1_FAILED=()
for ((i=1; i<=N_BATCHES_W1; i++)); do
  PARTIAL="$STACK/dev/extractions/batch-${i}-concepts.md"
  if ! "$SCRIPTS_DIR/assert-written.sh" "$PARTIAL" "$DISPATCH_EPOCH_W1" "concept-identifier" 2>/dev/null; then
    W1_FAILED+=("batch-${i}")
  fi
done
if (( ${#W1_FAILED[@]} > 0 )); then
  printf 'AGENT_WRITE_FAILURE: W1 batches ungated:\n'
  printf '  %s\n' "${W1_FAILED[@]}"
  exit 1
fi
```

## Step 6.5: W1b — Deterministic dedup in the parent

Group concept blocks across all W1 outputs by slug. For any slug appearing in multiple batches, merge `source_paths[]` into a single unified block. Compute `extraction_hash` per unique slug. Classify each unique slug as `new` (no `target_article` in any contributing block) or `updated`. All deterministic; no agent needed.

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

# Load the meta into shell vars.
source <(grep -E '^[A-Z_]+=' "$STACK/dev/extractions/_dedup-meta.txt" | sed 's/^/export /')
CONCEPT_SLUGS=($ALL_SLUGS)


# Compute extraction_hash per unique slug. Required byte format (stable across
# stacks; do not change without invalidating every skip list):
#   {path1}|{path2}|...|{pathN}|{slug}
# paths sorted ascending, joined by `|`, no trailing newline.
declare -A SLUG_HASH
for slug in "${CONCEPT_SLUGS[@]}"; do
  per_slug_path="$STACK/dev/extractions/_dedup-${slug}.md"
  paths=$(awk '/^source_paths:/{p=1;next} p && /^  - /{sub(/^  - /,""); print} p && !/^  -/{exit}' "$per_slug_path" | sort)
  hash=$(printf '%s' "$(echo "$paths" | tr '\n' '|')${slug}" | "$SCRIPTS_DIR/compute-extraction-hash.sh")
  SLUG_HASH[$slug]=$hash
done
```

The Python pass merges `source_paths[]` deterministically (set-of-seen with first-seen-order preservation) and writes a single canonical `_dedup.md` plus one `_dedup-{slug}.md` per unique slug. The `compute-extraction-hash.sh` invocation matches the byte format documented in `agents/article-synthesizer.md`.

## Step 6.75: W2 — Parent-side parallel article-synthesizer dispatch

Article-synthesizer is naturally 1-per-slug — each agent reads one `_dedup-{slug}.md` and writes one `articles/{slug}.md`. No batching needed.

**Wave cap: 25 agents per dispatch wave.** This matches the prior orchestrator's `W2_WAVE_CAP` to avoid overwhelming the harness on stacks with hundreds of new concepts. Each wave runs in parallel; waves run sequentially. Each wave captures its own dispatch epoch so the gate compares each wave's articles against the epoch immediately preceding their dispatch.

Each wave does, in order: (1) populate `extraction_hash` in each slug's per-slug dedup file from `${SLUG_HASH[$slug]}` so article-synthesizer can copy it verbatim into article frontmatter; (2) dispatch one `stacks:article-synthesizer` per slug in a single message; (3) gate every expected article against that wave's epoch. The hash injection MUST happen before dispatch — agents read the per-slug file at dispatch time, so a missing hash field at dispatch produces an article with empty `extraction_hash` frontmatter, breaking the W0b skip-list flywheel for the next catalog run.

```bash
W2_WAVE_CAP=25
n_w2_waves=0
DISPATCH_EPOCH_W2_FIRST=""
W2_FAILED=()
n=${#CONCEPT_SLUGS[@]}
i=0
while (( i < n )); do
  WAVE_SLICE=("${CONCEPT_SLUGS[@]:i:W2_WAVE_CAP}")

  # 1. Inject extraction_hash into each per-slug dedup file BEFORE dispatch.
  for slug in "${WAVE_SLICE[@]}"; do
    per_slug="$STACK/dev/extractions/_dedup-${slug}.md"
    if ! grep -q "^extraction_hash:" "$per_slug"; then
      sed -i "/^slug: ${slug}/a extraction_hash: ${SLUG_HASH[$slug]}" "$per_slug"
    fi
  done

  # 2. Capture epoch, then dispatch.
  DISPATCH_EPOCH_W2_WAVE=$(date +%s)
  [[ -z "$DISPATCH_EPOCH_W2_FIRST" ]] && DISPATCH_EPOCH_W2_FIRST="$DISPATCH_EPOCH_W2_WAVE"
  # In a single message, dispatch one stacks:article-synthesizer agent per slug
  # in WAVE_SLICE. Each prompt names:
  #   - $STACK/dev/extractions/_dedup-${slug}.md (concept block, self-contained,
  #     extraction_hash now populated)
  #   - $STACK/articles/${slug}.md if slug is in UPDATED_SLUGS (else absent)
  #   - $STACK/STACK.md (for source hierarchy + allowed_tags)
  # Tell each agent to copy extraction_hash verbatim from the concept block
  # frontmatter (W1b populated it; agents don't recompute).
  # ----- DISPATCH MARKER (parent does this) -----

  # 3. After fan-in, gate each article in this wave against this wave's epoch.
  for slug in "${WAVE_SLICE[@]}"; do
    if ! "$SCRIPTS_DIR/assert-written.sh" "$STACK/articles/${slug}.md" "$DISPATCH_EPOCH_W2_WAVE" "article-synthesizer" 2>/dev/null; then
      W2_FAILED+=("$slug")
    fi
  done
  ((i += W2_WAVE_CAP))
  ((n_w2_waves++))
done
if (( ${#W2_FAILED[@]} > 0 )); then
  printf 'AGENT_WRITE_FAILURE: W2 slugs ungated:\n'
  printf '  %s\n' "${W2_FAILED[@]}"
  exit 1
fi
```

**Summary write (parent):**

```bash
jq -n \
  --argjson n_sources "$N_SOURCES" \
  --argjson n_batches_w1 "$N_BATCHES_W1" \
  --argjson n_concepts_input "$INPUT_BLOCKS" \
  --argjson n_unique_concepts "$N_UNIQUE_CONCEPTS" \
  --argjson n_articles_new "$N_NEW" \
  --argjson n_articles_updated "$N_UPDATED" \
  --argjson n_w2_waves "$n_w2_waves" \
  --arg dispatch_epoch_w1 "$DISPATCH_EPOCH_W1" \
  --arg dispatch_epoch_w2 "$DISPATCH_EPOCH_W2_FIRST" \
  '{schema_version:1, wave:"w1-w2", status:"ok",
    counts:{n_sources:$n_sources, n_batches_w1:$n_batches_w1,
            n_concepts_input:$n_concepts_input, n_unique_concepts:$n_unique_concepts,
            n_articles_new:$n_articles_new, n_articles_updated:$n_articles_updated,
            n_w2_waves:$n_w2_waves},
    epochs:{dispatch_epoch_w1:$dispatch_epoch_w1, dispatch_epoch_w2:$dispatch_epoch_w2}}' \
  > "$STACK/dev/extractions/_w1-w2-summary.json"
rm -f "$STACK/dev/extractions/_dedup-meta.txt"
```

Downstream steps (W2b wikilink, W2b-post tag drift, W3 source filing, W4 MoC update) remain in this skill after Step 6.75 succeeds.

## Step 7: W2b — Wikilink pass

After all W2 assert-written gates pass, run the deterministic wikilink pass:

```bash
"$SCRIPTS_DIR/wikilink-pass.sh" "$STACK/articles/" "$STACK/glossary.md"
```

When `$STACK/glossary.md` does not exist (first catalog run before any audit pass), the script is a no-op. This is safe and expected.

The script reads bold terms from `glossary.md` and rewrites the first occurrence of each term per article as a `[[wikilink]]`. Self-links are excluded (when the article's own slug matches the term slug).

## Step 7.5: Tag drift check

After the wikilink pass, enforce the tag vocabulary declared in `STACK.md`. The check reads `allowed_tags:` from the stack root and halts the pipeline if any article carries an out-of-vocabulary tag. No auto-rewrite — drift is a surfaced defect the operator resolves by editing either the offending article or the vocabulary list.

```bash
"$SCRIPTS_DIR/normalize-tags.sh" "$STACK"
```

On non-zero exit, halt the catalog pipeline and surface the `TAG_DRIFT:` stderr lines to the user. Do not proceed to W3 (source filing) — sources for drifted articles stay in `incoming/` so the next run retries after the operator fixes the tags. When `allowed_tags:` is absent or empty, the script emits a `normalize-tags: allowed_tags not declared, skipping drift check` warning to stderr and exits 0 (backward-compat for stacks that haven't migrated).

## Step 8: W3 — Source filing

Move successfully synthesized source files from `sources/incoming/` to their publisher directory. Only move sources for which all expected articles passed their W2 assert-written gates. Failed articles block their sources' filing at W3 below.

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
dest_dir="$STACK/sources/${publisher:-unknown}"
mkdir -p "$dest_dir"
mv "$src_file" "$dest_dir/"
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

```bash
SUMMARY_PATH="$STACK/dev/extractions/_w1-w2-summary.json"
N_SOURCES=$(jq -r '.counts.n_sources' "$SUMMARY_PATH")
N_ARTICLES_NEW=$(jq -r '.counts.n_articles_new' "$SUMMARY_PATH")
N_ARTICLES_UPDATED=$(jq -r '.counts.n_articles_updated' "$SUMMARY_PATH")

NEW_ENTRY="## [$(date +%Y-%m-%d)] catalog | $N_SOURCES new sources, $N_ARTICLES_NEW articles created, $N_ARTICLES_UPDATED articles updated
Sources processed: $N_SOURCES. New articles: $N_ARTICLES_NEW. Updated articles: $N_ARTICLES_UPDATED."

{ printf '%s\n\n' "$NEW_ENTRY"; cat "$STACK/log.md"; } > /tmp/stacks-log.tmp
mv /tmp/stacks-log.tmp "$STACK/log.md"
```

Commit the stack:

```bash
git add "$STACK/"
git commit -m "feat($STACK): catalog $N_SOURCES sources, $N_ARTICLES_NEW new articles, $N_ARTICLES_UPDATED updated"
```

Report summary to the user:
- How many sources were processed
- How many articles were created vs updated
- Whether any sources remain in `incoming/` (failed W2 gates) and what to do about them
- Suggest running `/stacks:audit-stack $STACK` next if 2+ articles exist
