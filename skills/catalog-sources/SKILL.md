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
TELEMETRY_SH=$(find ~/.claude/plugins/cache -name telemetry.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
if [[ -z "$TELEMETRY_SH" ]]; then
  STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
  TELEMETRY_SH="$STACKS_ROOT/scripts/telemetry.sh"
fi
SKILL_NAME="stacks:catalog-sources" bash "$TELEMETRY_SH" 2>/dev/null || true
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

Anchor on the `scripts/` subdirectory under the plugin cache (path-guarded so a similarly-named dir from another plugin cannot collide), then derive every other plugin path from the shared root:

```bash
# Prefer installLocation from known_marketplaces.json — authoritative for
# directory-source installs. Fall back to a cache scan only when that field
# is not set (registry-style installs).
STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
if [[ -z "$STACKS_ROOT" ]]; then
  SCRIPTS_DIR=$(find ~/.claude/plugins/cache -type d -name "scripts" -path "*/stacks/*" 2>/dev/null | sort -V | tail -1)
  STACKS_ROOT="${SCRIPTS_DIR%/scripts}"
else
  SCRIPTS_DIR="$STACKS_ROOT/scripts"
fi

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
  SKIP_HASHES=$(awk '
    /^- id:/ { in_item=1; hash=""; status="" }
    in_item && /extraction_hash:/ { hash=$2 }
    in_item && /status:/ { status=$2 }
    in_item && /^$/ {
      if (status=="applied" || status=="closed") print hash
      in_item=0
    }
  ' "$FINDINGS")
  SKIP_COUNT=$(echo "$SKIP_HASHES" | grep -c . || echo 0)
  echo "W0b: loaded $SKIP_COUNT extraction_hash values to skip (terminal-status findings)"
else
  echo "W0b: no prior findings.md; skip list is empty (first catalog run)"
fi
```

Missing `findings.md` is a no-op; skip list is empty on the first run.

## Step 6: W1 + W1b + W2 — Orchestrator dispatch

Dispatch a single `concept-identifier-orchestrator` agent via the Task tool. The orchestrator owns the W1 concept-identifier fan-out (using the #26 batch math), the W1b dedup awk + `compute-extraction-hash.sh` loop, and the W2 article-synthesizer fan-out. It gates every expected output via `assert-written.sh` and writes a summary JSON the main session reads at Step 10.

Pass the orchestrator as task content:
- `$STACK`: stack root path.
- `$SCRIPTS_DIR`: for `assert-written.sh` and `compute-extraction-hash.sh`.
- `$NEW_SOURCES`: newline-separated source paths (from Step 4).
- `$SKIP_HASHES`: the W0b skip list (may be empty).

The orchestrator writes `$STACK/dev/extractions/_orchestrator-summary.json` with the catalog-run counts (see its contract) and returns a final JSON line of the form:

```json
{"status": "ok", "summary_path": "dev/extractions/_orchestrator-summary.json", "n_articles_new": N, "n_articles_updated": M}
```

The main session's gate parses the returned text for a valid summary-OK line AND confirms the summary file exists. Either signal missing = catalog-run failure. On failure the orchestrator emits a `CATALOG_ORCHESTRATOR_FAILED:` marker on stdout and reports failed batch ids / slugs on stderr.

```bash
# After orchestrator returns, confirm the returned text reports status:ok AND
# the summary file exists AND the required fields are present with correct
# types. Type-checks (not truthiness) because zero counts are valid on
# incremental runs where every source is already in the skip list.
SUMMARY_PATH="$STACK/dev/extractions/_orchestrator-summary.json"
if ! printf '%s\n' "$ORCH_RESPONSE" | grep -q '"status".*"ok"'; then
  echo "AGENT_WRITE_FAILURE: concept-identifier-orchestrator returned no status:ok line" >&2
  exit 1
fi
if [[ ! -s "$SUMMARY_PATH" ]]; then
  echo "AGENT_WRITE_FAILURE: _orchestrator-summary.json missing" >&2
  exit 1
fi
if ! jq -e '(.n_articles_new | type) == "number" and (.n_articles_updated | type) == "number" and (.new_slugs | type) == "array" and (.updated_slugs | type) == "array"' "$SUMMARY_PATH" >/dev/null 2>&1; then
  echo "AGENT_WRITE_FAILURE: _orchestrator-summary.json missing or wrong-typed required fields" >&2
  exit 1
fi
```

Downstream steps (W2b wikilink, W2b-post tag drift, W3 source filing, W4 MoC update) remain in this skill after the orchestrator returns successfully.

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
ARTICLES_DIR="$STACK/articles"
INDEX="$STACK/index.md"

# 1. Extract and preserve the ## Reading Paths section from the existing index.md
READING_PATHS_BLOCK=""
if [[ -f "$INDEX" ]]; then
  READING_PATHS_BLOCK=$(awk '
    /^## Reading Paths/ { in_section=1 }
    in_section { buf = buf $0 "\n" }
    /^## / && !/^## Reading Paths/ && in_section { in_section=0; sub(/\n[^\n]*\n$/, "", buf) }
    END { if (in_section) print buf; else print buf }
  ' "$INDEX")
fi

# 2. Gather all articles and group by tags[0]
declare -A TAG_GROUPS
while IFS= read -r article; do
  tag=$(awk '/^tags:/{found=1; next} found && /^  - /{print $2; exit} found && !/^  -/{exit}' "$article")
  title=$(awk '/^title:/{print substr($0, 8); exit}' "$article")
  slug=$(basename "$article" .md)
  tag="${tag:-uncategorized}"
  TAG_GROUPS["$tag"]+="- [[${slug}|${title}]]\n"
done < <(find "$ARTICLES_DIR" -maxdepth 1 -name '*.md' | sort)

# 3. Write new index.md
{
  echo "# $(basename "$STACK"): Map of Contents"
  echo ""
  echo "*Auto-generated from article frontmatter. Edit only the Reading Paths section below.*"
  echo ""
  echo "## Articles"
  echo ""
  for tag in $(echo "${!TAG_GROUPS[@]}" | tr ' ' '\n' | sort); do
    echo "### ${tag}"
    echo ""
    printf "${TAG_GROUPS[$tag]}"
    echo ""
  done
  if [[ -n "$READING_PATHS_BLOCK" ]]; then
    echo ""
    printf '%s\n' "$READING_PATHS_BLOCK"
  fi
} > "$INDEX"
```

The `## Reading Paths` section is preserved verbatim. Any user-curated reading path content in that section survives across catalog runs unchanged. All other sections (title, generated article groupings by `tags[0]`) are rewritten.

## Step 10: Log + commit

Prepend an entry to `$STACK/log.md`:

```bash
SUMMARY_PATH="$STACK/dev/extractions/_orchestrator-summary.json"
N_SOURCES=$(jq -r '.n_sources' "$SUMMARY_PATH")
N_ARTICLES_NEW=$(jq -r '.n_articles_new' "$SUMMARY_PATH")
N_ARTICLES_UPDATED=$(jq -r '.n_articles_updated' "$SUMMARY_PATH")

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
