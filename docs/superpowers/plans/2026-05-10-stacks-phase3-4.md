# Stacks Phase 3+4 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add quality gate to process-inbox (#40), scheduled maintenance loop (#14), on-demand guide synthesis (#18), and comparison page type (#7).

**Architecture:** Phase 3 (Tasks 1-2) touches existing SKILL.md files and adds a loop script. Phase 4 (Tasks 3-4) adds new skills and agents. All four tasks are independent — any execution order works, though Task 4 should come after Task 3 so the comparison page design can reference the guide synthesis shape.

**Tech Stack:** Bash, bats (mechanical test coverage only — SKILL.md files are LLM instructions and verified by smoke test), SKILL.md natural-language instructions.

---

## Design stub: #10 qmd search integration

**Do NOT start this without resolving three decisions:**

1. **Is qmd available?** The stacks issue references qmd from llm-wiki (Karpathy's project). Verify it has a stable release, installable via pip/brew, with a documented CLI.
2. **What is qmd's CLI interface?** The integration needs an exact call signature — e.g., `qmd search --query "..." --db "$LIBRARY/.qmd/index.db" --top 5`. This can only come from reading qmd's own docs/README.
3. **Deployment model:** shell exec vs MCP server. The issue says "MCP server option avoids shell exec overhead per query." Which to implement first? Probably shell exec as MVP with MCP noted in docs.

Once resolved: `/stacks:ask` detects `$LIBRARY/.qmd/` and routes retrieval through qmd. The `<!-- STACKS-SEARCH STUB -->` comment in ask SKILL.md Step 5 is the exact swap point.

---

### Task 1: Quality gate in process-inbox (#40)

**Goal:** process-inbox reads file body content and moves low-quality files to `$LIBRARY/recycling-bin/` instead of routing them to a stack's incoming dir.

**Files:**
- Modify: `skills/process-inbox/SKILL.md` — add quality assessment in Step 4, RECYCLED list, recycling-bin mkdir, Recycled section in Step 6 report, recycling-bin in Step 5 git add
- Create: `templates/library/recycling-bin/.gitkeep` — scaffold recycling-bin at library init time (init.sh copies templates/library/ verbatim)

**Acceptance Criteria:**
- [ ] Files with specific, non-obvious technical facts route to stack incoming/ as normal
- [ ] Files with only generic content (process wisdom, meeting notes, API restatements) move to recycling-bin/
- [ ] recycling-bin/ is created lazily in process-inbox when first needed
- [ ] Step 6 report includes "Recycled (N):" section when any files are recycled (omitted when empty, matching existing pattern)
- [ ] `templates/library/recycling-bin/.gitkeep` exists so new libraries get the directory on scaffold

**Verify:** Manual smoke test in a test library — add a low-quality file ("meeting summary, no technical facts") and a high-quality file ("specific failure mode with cause and symptom"), run `/stacks:process-inbox`, confirm high-quality file routes to stack incoming/ and low-quality file moves to recycling-bin/.

**Steps:**

- [ ] **Step 1: Add recycling-bin to library template**

```bash
mkdir -p /home/chris/2_project-files/projects/active-projects/stacks/templates/library/recycling-bin
touch /home/chris/2_project-files/projects/active-projects/stacks/templates/library/recycling-bin/.gitkeep
```

Verify: `ls templates/library/recycling-bin/` → shows `.gitkeep`

- [ ] **Step 2: Update process-inbox SKILL.md Step 4 — add RECYCLED list and quality gate**

In `skills/process-inbox/SKILL.md`:

**2a.** In the paragraph that introduces the three tracking lists (MOVED, UNMATCHED, TIES), add RECYCLED as a fourth list: "Track four lists throughout this step: MOVED, UNMATCHED, TIES, RECYCLED."

**2b.** After the domain classification determines a file matches a stack, and **before** the `mv "$f" "$dest"` shell block that routes the file, add this quality gate:

```
**Quality gate** — before routing a matched file, read its body content beyond section
headers: at minimum the first 600 words (exclude `##` headings and lines under 20 chars).

Assess: **Does this file contain at least one specific, non-obvious technical fact,
failure mode, or concrete architectural decision a practitioner would look up?**

Pass signals (route to stack):
- Specific failure mode with concrete cause and symptom (e.g., "`flock -n` silently
  drops events when a consumer loop is already inside the lock — use blocking `flock`")
- Measured performance or behavior claim tied to specific conditions
- Discovered constraint with traceable cause and effect
- Concrete architectural decision with documented consequences

Fail signals (route to recycling-bin/):
- Restatement of documented API semantics — things findable in official docs
- Generic process aphorisms without specific technical grounding ("test before merge")
- Meeting summaries or status updates with no extractable technical fact
- Observations that follow directly from understanding how the system works

For files that fail quality:
```bash
mkdir -p "$LIBRARY/recycling-bin"
mv "$f" "$LIBRARY/recycling-bin/$filename"
echo "Recycled: $filename → recycling-bin/ (low quality)"
```

Add to RECYCLED list. Do NOT add to MOVED.

For files that pass quality: route to stack incoming/ as before.
```

- [ ] **Step 3: Update Step 5 (commit) to stage recycling-bin**

In Step 5 of process-inbox SKILL.md, update the `git add` line to include `recycling-bin/` when RECYCLED is non-empty:

When RECYCLED is non-empty, the commit command becomes:
```bash
cd "$LIBRARY"
git add -A inbox/ {each affected stack}/sources/incoming/ recycling-bin/
git commit -m "chore(inbox): route {N_MOVED} file(s), recycle {N_RECYCLED} low-quality file(s)"
```

When RECYCLED is empty, keep the original commit message and don't add `recycling-bin/` to the staged paths.

- [ ] **Step 4: Update Step 6 report to include Recycled section**

In Step 6 of process-inbox SKILL.md, add after the Tied section:

```
Recycled — moved to recycling-bin/ (N):
  {filename}  (low quality: no specific technical facts found)
```

Omit this section if RECYCLED is empty, matching the existing pattern for Unmatched and Tied.

- [ ] **Step 5: Commit**

```bash
git add templates/library/recycling-bin/.gitkeep skills/process-inbox/SKILL.md
git commit -m "feat(#40): quality gate in process-inbox — low-quality files to recycling-bin"
```

- [ ] **Step 6: Version bump + CHANGELOG**

```bash
jq --arg v "0.20.0" '.version = $v' .claude-plugin/plugin.json > /tmp/plugin.json && mv /tmp/plugin.json .claude-plugin/plugin.json
jq --arg v "0.20.0" '.plugins[0].version = $v' .claude-plugin/marketplace.json > /tmp/marketplace.json && mv /tmp/marketplace.json .claude-plugin/marketplace.json
```

Prepend to CHANGELOG.md:

```markdown
## [0.20.0] — 2026-05-10

### Added
- process-inbox: quality gate — files with no specific technical content route to `recycling-bin/` instead of stack incoming dirs (#40)
- templates/library: scaffold `recycling-bin/` directory at library init time
```

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md
git commit -m "chore: bump to 0.20.0, #40 quality gate CHANGELOG"
git push
gh issue close 40 --repo chuggies510/stacks --comment "Quality gate added to process-inbox in 0.20.0. Low-quality files route to recycling-bin/ instead of stack incoming dirs."
```

---

### Task 2: Scheduled loop — process-inbox + catalog-sources on a timer (#14)

**Goal:** `scripts/loop.sh` does mechanical inbox routing (keyword scoring, no LLM) then invokes `catalog-sources` via `claude -p` for each stack that received files. Enable/disable via `$LIBRARY/.loop-enabled` sentinel. Bats tests cover mechanical logic; the `claude -p` calls are mocked.

**Files:**
- Create: `scripts/loop.sh`
- Create: `tests/loop.bats`

**Acceptance Criteria:**
- [ ] Script exits 0 when `$LIBRARY/.loop-enabled` is absent (disabled, no-op, logs "disabled")
- [ ] Script exits 0 when inbox is empty (logs timestamp + "inbox empty")
- [ ] Script routes inbox `.md` files to stack incoming/ using keyword scoring against STACK.md scope sections (threshold ≥2 matching keywords)
- [ ] Script invokes `claude -p "/stacks:catalog-sources {stack}"` for each stack with newly routed files
- [ ] Script skips `claude -p` when no files were routed
- [ ] All activity appended to `$LIBRARY/loop.log` with ISO-8601 timestamps
- [ ] `bats tests/loop.bats` passes (all 7 tests)
- [ ] Script uses `STACKS_CONFIG` env var override for testability (falls back to `~/.config/stacks/config.json`)

**Verify:** `bats tests/loop.bats` → all 7 tests pass. Manual smoke test: `touch $LIBRARY/.loop-enabled && bash scripts/loop.sh` from a library with one inbox file → file routed, loop.log written, `claude -p` invoked.

**Steps:**

- [ ] **Step 1: Write failing bats tests**

Create `tests/loop.bats`:

```bash
#!/usr/bin/env bats

setup() {
  TEST_TMP=$(mktemp -d)
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/loop.sh"

  # Library structure
  mkdir -p "$TEST_TMP/lib/inbox"
  mkdir -p "$TEST_TMP/lib/mystack/sources/incoming"
  printf '# My Stack\n\n## Scope\n\nCovers the svelte framework, reactivity system, components, runes, and stores.\n' \
    > "$TEST_TMP/lib/mystack/STACK.md"

  # Fake config
  printf '{"library": "%s/lib"}' "$TEST_TMP" > "$TEST_TMP/config.json"

  # Mock claude binary — records calls, exits 0
  mkdir -p "$TEST_TMP/bin"
  printf '#!/usr/bin/env bash\necho "MOCK_CLAUDE: $*" >> "%s/claude-calls.log"\n' \
    "$TEST_TMP" > "$TEST_TMP/bin/claude"
  chmod +x "$TEST_TMP/bin/claude"

  export STACKS_CONFIG="$TEST_TMP/config.json"
  export PATH="$TEST_TMP/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "exits 0 when .loop-enabled missing (disabled)" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"disabled"* ]]
}

@test "exits 0 and logs no-op when inbox is empty" {
  touch "$TEST_TMP/lib/.loop-enabled"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"inbox empty"* ]]
  [ -f "$TEST_TMP/lib/loop.log" ]
  grep -q "inbox empty" "$TEST_TMP/lib/loop.log"
}

@test "log entries have ISO-8601 timestamp format" {
  touch "$TEST_TMP/lib/.loop-enabled"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qE '\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\]' "$TEST_TMP/lib/loop.log"
}

@test "does not call claude when inbox is empty" {
  touch "$TEST_TMP/lib/.loop-enabled"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TMP/claude-calls.log" ]
}

@test "routes inbox file to best-matching stack incoming/" {
  touch "$TEST_TMP/lib/.loop-enabled"
  printf '# Svelte Runes\n\nsvelte reactivity system runes notes\n' \
    > "$TEST_TMP/lib/inbox/runes.md"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TMP/lib/mystack/sources/incoming/runes.md" ]
  [ ! -f "$TEST_TMP/lib/inbox/runes.md" ]
}

@test "calls claude catalog-sources for stack with new incoming files" {
  touch "$TEST_TMP/lib/.loop-enabled"
  printf '# Svelte Runes\n\nsvelte reactivity system runes notes\n' \
    > "$TEST_TMP/lib/inbox/runes.md"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "catalog-sources mystack" "$TEST_TMP/claude-calls.log"
}

@test "skips claude when no inbox files match any stack" {
  touch "$TEST_TMP/lib/.loop-enabled"
  printf '# Cooking Recipe\n\nIngredients: flour, water, salt.\n' \
    > "$TEST_TMP/lib/inbox/recipe.md"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TMP/claude-calls.log" ]
}
```

Run: `bats tests/loop.bats` → expected: all 7 fail (script doesn't exist yet).

- [ ] **Step 2: Write scripts/loop.sh**

```bash
#!/usr/bin/env bash
# Scheduled library maintenance: route inbox files (keyword matching), then catalog per stack.
#
# Add to crontab (crontab -e):
#   0 * * * * PATH="$HOME/.local/bin:$HOME/.nvm/default/bin:/usr/local/bin:$PATH" \
#             bash /path/to/stacks/scripts/loop.sh
#
# Enable for a library:  touch "$LIBRARY/.loop-enabled"
# Disable:               rm "$LIBRARY/.loop-enabled"
#
# Note: 'claude' must be in PATH at cron time (see crontab PATH line above).
# Routing is keyword-based (not LLM) — some imprecision is acceptable for
# unattended runs. For precision routing, run /stacks:process-inbox manually.
set -euo pipefail

CONFIG="${STACKS_CONFIG:-$HOME/.config/stacks/config.json}"
[[ -f "$CONFIG" ]] || { echo "[loop] no config at $CONFIG"; exit 0; }

LIBRARY=$(jq -r '.library // empty' "$CONFIG")
LIBRARY="${LIBRARY/#\~/$HOME}"
[[ -d "$LIBRARY" ]] || { echo "[loop] library not found: $LIBRARY"; exit 0; }

LOG="$LIBRARY/loop.log"
log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG"; }

# Sentinel check
[[ -f "$LIBRARY/.loop-enabled" ]] || { log "disabled (.loop-enabled absent)"; exit 0; }

# No-op if inbox is empty
mapfile -t inbox_files < <(find "$LIBRARY/inbox" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)
if [[ ${#inbox_files[@]} -eq 0 ]]; then
  log "inbox empty — no-op"
  exit 0
fi

log "routing ${#inbox_files[@]} inbox file(s)..."

declare -A stack_hit_count

for f in "${inbox_files[@]}"; do
  filename=$(basename "$f")
  file_words=$(cat "$f" | tr '[:upper:]' '[:lower:]' | grep -oE '[a-z]{4,}' | sort -u)
  best_stack=""
  best_score=0

  for stack_dir in "$LIBRARY"/*/; do
    [[ -f "${stack_dir}STACK.md" ]] || continue
    stack=$(basename "$stack_dir")

    # Extract keywords from STACK.md Scope section
    scope=$(awk '/^## Scope/,/^## /' "${stack_dir}STACK.md" 2>/dev/null | tail -n +2 | head -20)
    scope_words=$(echo "$scope" | tr '[:upper:]' '[:lower:]' | grep -oE '[a-z]{4,}' | sort -u)

    score=0
    while IFS= read -r word; do
      [[ -z "$word" ]] && continue
      echo "$file_words" | grep -qxF "$word" && score=$((score + 1))
    done <<< "$scope_words"

    if [[ "$score" -gt "$best_score" ]]; then
      best_score="$score"
      best_stack="$stack"
    fi
  done

  if [[ "$best_score" -ge 2 && -n "$best_stack" ]]; then
    dest_dir="$LIBRARY/$best_stack/sources/incoming"
    mkdir -p "$dest_dir"
    dest="$dest_dir/$filename"
    if [[ -f "$dest" ]]; then
      base="${filename%.*}"; ext="${filename##*.}"; n=2
      while [[ -f "$dest_dir/${base}-${n}.${ext}" ]]; do n=$((n + 1)); done
      dest="$dest_dir/${base}-${n}.${ext}"
    fi
    mv "$f" "$dest"
    log "routed: $filename → $best_stack/sources/incoming/ (score=$best_score)"
    stack_hit_count["$best_stack"]=$((${stack_hit_count["$best_stack"]:-0} + 1))
  else
    log "unmatched: $filename (best_score=$best_score) — left in inbox"
  fi
done

if [[ ${#stack_hit_count[@]} -eq 0 ]]; then
  log "no files routed — skipping catalog"
  exit 0
fi

for stack in "${!stack_hit_count[@]}"; do
  n="${stack_hit_count[$stack]}"
  log "cataloging $stack ($n file(s))..."
  cd "$LIBRARY"
  claude -p "/stacks:catalog-sources $stack" >> "$LOG" 2>&1 \
    || log "catalog-sources failed for $stack (see log above)"
done

log "done"
```

- [ ] **Step 3: Run tests**

```bash
bats tests/loop.bats
```

Expected: all 7 tests pass. If the routing tests fail on score threshold, check that the bats setup STACK.md scope has enough keywords (≥4 distinct 4-char words) and the inbox file content overlaps at least 2 of them.

- [ ] **Step 4: Commit**

```bash
git add scripts/loop.sh tests/loop.bats
git commit -m "feat(#14): scheduled loop — mechanical routing + claude catalog-sources per stack"
```

- [ ] **Step 5: Version bump + CHANGELOG**

```bash
jq --arg v "0.21.0" '.version = $v' .claude-plugin/plugin.json > /tmp/plugin.json && mv /tmp/plugin.json .claude-plugin/plugin.json
jq --arg v "0.21.0" '.plugins[0].version = $v' .claude-plugin/marketplace.json > /tmp/marketplace.json && mv /tmp/marketplace.json .claude-plugin/marketplace.json
```

Prepend to CHANGELOG.md:

```markdown
## [0.21.0] — 2026-05-10

### Added
- scripts/loop.sh: scheduled library maintenance — route inbox files (keyword matching, no LLM) then catalog per stack via `claude -p`. Enable with `touch $LIBRARY/.loop-enabled`. Add to crontab with explicit PATH including claude's install dir. (#14)

### Notes
- Routing threshold: ≥2 keyword matches between file content and stack STACK.md scope. Files below threshold stay in inbox with a log entry.
- `claude` must be in PATH at cron time. Example crontab: `0 * * * * PATH="$HOME/.local/bin:/usr/local/bin:$PATH" bash /path/to/loop.sh`
```

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md
git commit -m "chore: bump to 0.21.0, #14 loop CHANGELOG"
git push
gh issue close 14 --repo chuggies510/stacks --comment "Scheduled loop script added in 0.21.0 (scripts/loop.sh). Enable with touch \$LIBRARY/.loop-enabled. Routing is keyword-based; use /stacks:process-inbox for precision."
```

---

### Task 3: /stacks:guide on-demand synthesis (#18)

**Goal:** New `/stacks:guide "{topic}"` skill retrieves relevant articles across stacks and synthesizes a structured long-form guide, writing it to `$LIBRARY/guides/{slug}.md`. `/stacks:ask` surfaces existing guides before doing article retrieval.

**Files:**
- Create: `skills/guide/SKILL.md`
- Create: `templates/library/guides/.gitkeep` — scaffold guides/ at library init time
- Modify: `skills/ask/SKILL.md` — add Step 1b to check existing guides before article retrieval

**Acceptance Criteria:**
- [ ] `skills/guide/SKILL.md` exists with correct frontmatter (name, description)
- [ ] Guide written to `$LIBRARY/guides/{slug}.md` with frontmatter: topic, generated, stacks, articles (with commit SHAs), excluded
- [ ] `--stacks` flag scopes retrieval to named stacks (same comma-separated format as /stacks:ask)
- [ ] `--regenerate` flag bypasses existing guide check and overwrites
- [ ] Guide body: 800-2000 words, structured sections (Overview, Key Concepts, Patterns, Pitfalls, Field Notes, Sources)
- [ ] `/stacks:ask` Step 1b checks `$LIBRARY/guides/` before article retrieval and surfaces matching guide
- [ ] `templates/library/guides/.gitkeep` exists

**Verify:** Manual smoke test in a test library with at least 2 articles cataloged:
```bash
/stacks:guide "svelte reactivity"
# → guides/svelte-reactivity.md written
# → frontmatter has: topic, generated, stacks, articles (each with stack/path/sha), excluded
# → body has: Overview, Key Concepts, Patterns, Pitfalls, Sources sections

/stacks:guide "svelte reactivity" --regenerate
# → guide overwritten (updated generated date)

/stacks:ask "svelte reactivity"
# → surfaces guides/svelte-reactivity.md instead of doing fresh article retrieval
```

**Steps:**

- [ ] **Step 1: Create guides/ in library template**

```bash
mkdir -p templates/library/guides
touch templates/library/guides/.gitkeep
```

- [ ] **Step 2: Write skills/guide/SKILL.md**

Create `skills/guide/SKILL.md`:

```markdown
---
name: guide
description: |
  Use when the user wants a long-form synthesized guide on a topic from their
  knowledge library. Retrieves relevant articles across stacks and writes a
  structured guide to library/guides/{slug}.md. Supports --stacks to scope to
  specific stacks and --regenerate to rebuild an existing guide.
  Examples: "/stacks:guide 'HVAC building electrification'",
  "/stacks:guide 'Svelte runes' --stacks svelte",
  "/stacks:guide 'schema migration' --regenerate".
---

# Guide Synthesis

Generate a long-form guide from library articles.

## Step 0: Telemetry

\`\`\`bash
LOCATE=$(find ~/.claude/plugins/cache -name locate-plugin-root.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
[[ -z "$LOCATE" ]] && LOCATE="$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)/scripts/locate-plugin-root.sh"
STACKS_ROOT=$(bash "$LOCATE" 2>/dev/null)
SKILL_NAME="stacks:guide" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
\`\`\`

## Step 1: Find the library

\`\`\`bash
CONFIG="$HOME/.config/stacks/config.json"
if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: No stacks config found at $CONFIG. Run /stacks:init-library first."
  exit 1
fi
LIBRARY=$(jq -r '.library // empty' "$CONFIG")
LIBRARY="${LIBRARY/#\~/$HOME}"
if [[ -z "$LIBRARY" || ! -d "$LIBRARY" ]]; then
  echo "ERROR: Library not found at '$LIBRARY'."
  exit 1
fi
\`\`\`

## Step 2: Parse arguments

`$ARGUMENTS` contains the full argument string. Parse flags before extracting the topic:

\`\`\`bash
RAW="$ARGUMENTS"
STACKS_FILTER=""
REGENERATE=0

if [[ "$RAW" == *"--regenerate"* ]]; then
  REGENERATE=1
  RAW="${RAW//--regenerate/}"
fi

if [[ "$RAW" == *"--stacks "* ]]; then
  STACKS_FILTER=$(echo "$RAW" | sed 's/.*--stacks[[:space:]]*//' | awk '{print $1}')
  RAW=$(echo "$RAW" | sed "s/--stacks[[:space:]]*${STACKS_FILTER}//")
fi

# Strip surrounding quotes from topic
TOPIC=$(echo "$RAW" | sed "s/^['\"]//;s/['\"]$//" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

if [[ -z "$TOPIC" ]]; then
  echo "ERROR: Topic required. Example: /stacks:guide 'HVAC building electrification'"
  exit 1
fi

# Compute slug from topic
SLUG=$(echo "$TOPIC" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
\`\`\`

## Step 3: Check for existing guide

\`\`\`bash
GUIDE_PATH="$LIBRARY/guides/${SLUG}.md"
mkdir -p "$LIBRARY/guides"
\`\`\`

If `$GUIDE_PATH` exists and `REGENERATE=0`:
- Read the guide and display its content to the user
- Tell the user: "Existing guide found (generated: {date from frontmatter}). Displaying it below. Use `/stacks:guide --regenerate '{TOPIC}'` to rebuild from current articles."
- Stop.

If `$GUIDE_PATH` exists and `REGENERATE=1`: continue to Step 4 (will overwrite).

## Step 4: Resolve stack scope

Read `$LIBRARY/catalog.md`. Resolve `STACKS_TO_SEARCH`:

\`\`\`bash
if [[ -n "$STACKS_FILTER" ]]; then
  IFS=',' read -ra _RAW <<< "$STACKS_FILTER"
  STACKS_TO_SEARCH=()
  for s in "${_RAW[@]}"; do
    s="${s//[[:space:]]/}"
    [[ -n "$s" ]] || continue
    [[ -d "$LIBRARY/$s" ]] || { echo "ERROR: stack '$s' not found"; exit 1; }
    STACKS_TO_SEARCH+=("$s")
  done
else
  mapfile -t STACKS_TO_SEARCH < <(
    grep '^- \[' "$LIBRARY/catalog.md" \
    | sed 's|.*\[\([^]]*\)\](\([^/]*\)/).*|\2|'
  )
  [[ ${#STACKS_TO_SEARCH[@]} -gt 0 ]] \
    || { echo "No stacks in catalog.md — run /stacks:new-stack first."; exit 1; }
fi
\`\`\`

## Step 5: Load indexes and score articles

For each stack in `STACKS_TO_SEARCH`:
- Read `$LIBRARY/{stack}/index.md`. If it doesn't exist, note "no index yet" and skip.
- Capture any Reading Paths or Topics section as retrieval context.

Score articles across all stacks by topic relevance:
1. `title` frontmatter — highest weight
2. `tags[]` — high weight
3. Slug (filename without `.md`) — medium weight
4. Reading Paths / Topics sections from index — contextual aid

For guide synthesis, collect the top **10** articles globally (not capped at 3 like /stacks:ask — guides benefit from more source material). Track stack attribution for each. Note articles that were candidates but below threshold in an EXCLUDED list.

Read each selected article file.

If no relevant articles found: "No articles matched '{TOPIC}' in stacks: {STACKS_TO_SEARCH[*]}. Run /stacks:catalog-sources to process pending sources."

## Step 6: Record article commit SHAs

For each included article, capture its current commit SHA:

\`\`\`bash
for article_path in "${INCLUDED_ARTICLES[@]}"; do
  sha=$(git -C "$LIBRARY" log -1 --format="%H" -- "$article_path" 2>/dev/null || echo "")
  # store (stack_name, relative_path, sha) as a tuple
done
\`\`\`

## Step 7: Synthesize guide

Using all selected article content, synthesize a structured guide. Requirements:
- Open with an Overview that defines the topic and states its scope
- Sections appropriate to the topic; for technical topics use: Overview, Key Concepts, Patterns, Pitfalls, Field Notes, Sources
- Specific data points, formulas, rules of thumb, and failure modes drawn from articles
- Inline `[article-slug]` citations on every non-obvious claim
- 800-2000 words (longer than an article, shorter than a book chapter)

## Step 8: Write guide to library

Write `$LIBRARY/guides/${SLUG}.md`:

Frontmatter:
\`\`\`yaml
---
topic: "{TOPIC}"
generated: {YYYY-MM-DD today}
stacks:
  - {contributing stack name}
articles:
  - stack: {stack-name}
    path: {relative path from library root}
    sha: {commit sha}
excluded:
  - path: {relative path}
    reason: {reason for exclusion}
---
\`\`\`

Body: the synthesized guide from Step 7.

## Step 9: Update log.md for contributing stacks

For each stack that contributed articles, prepend to `$LIBRARY/{stack}/log.md`:

\`\`\`
## [YYYY-MM-DD] guide | "{TOPIC}" → guides/{SLUG}.md
Contributed {N} article(s) to guide synthesis.
\`\`\`

## Step 10: Commit and report

\`\`\`bash
cd "$LIBRARY"
git add guides/ {each contributing stack}/log.md
git commit -m "feat: synthesize guide — {SLUG}"
\`\`\`

Report to user:
\`\`\`
## Guide Complete

Topic: {TOPIC}
Written to: guides/{SLUG}.md
Sources: {N} articles from {stacks}

Run /stacks:guide --regenerate '{TOPIC}' to refresh after new sources are cataloged.
\`\`\`
```

- [ ] **Step 3: Update skills/ask/SKILL.md — add Step 1b guide check**

In `skills/ask/SKILL.md`, add a new `## Step 1b: Check existing guides` section immediately after `## Step 1: Find the library` and before `## Step 2: Read the catalog`.

Content of the new step:

```markdown
## Step 1b: Check existing guides

Compute a slug from the raw query (stripping any --stack/--stacks flags):

\`\`\`bash
QUERY_RAW="$ARGUMENTS"
QUERY_RAW=$(echo "$QUERY_RAW" | sed 's/--stack[[:space:]]*[^[:space:]]*//' | sed 's/--stacks[[:space:]]*[^[:space:]]*//')
QUERY_SLUG=$(echo "$QUERY_RAW" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
\`\`\`

If `$LIBRARY/guides/${QUERY_SLUG}.md` exists:
- Read the guide file
- Tell the user: "Returning existing guide for '{QUERY_SLUG}' (generated: {date from frontmatter}). Run `/stacks:guide --regenerate '{query}'` to synthesize a fresh guide from current articles."
- Display the guide content
- Stop — do not proceed to article retrieval.

If no matching guide exists: continue to Step 2.
```

- [ ] **Step 4: Commit**

```bash
git add skills/guide/SKILL.md templates/library/guides/.gitkeep skills/ask/SKILL.md
git commit -m "feat(#18): /stacks:guide on-demand synthesis + ask guide-first check"
```

- [ ] **Step 5: Version bump + CHANGELOG**

```bash
jq --arg v "0.22.0" '.version = $v' .claude-plugin/plugin.json > /tmp/plugin.json && mv /tmp/plugin.json .claude-plugin/plugin.json
jq --arg v "0.22.0" '.plugins[0].version = $v' .claude-plugin/marketplace.json > /tmp/marketplace.json && mv /tmp/marketplace.json .claude-plugin/marketplace.json
```

Prepend to CHANGELOG.md:

```markdown
## [0.22.0] — 2026-05-10

### Added
- /stacks:guide: new skill — synthesizes long-form guide from library articles (#18)
  - `--stacks` flag scopes retrieval to named stacks
  - `--regenerate` flag rebuilds an existing guide from current articles
  - Guides written to `library/guides/{slug}.md` with full article attribution and commit SHAs
- /stacks:ask: checks `library/guides/` before article retrieval and surfaces matching guide (Step 1b)
- templates/library: scaffold `guides/` directory at library init time
```

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md
git commit -m "chore: bump to 0.22.0, #18 guide CHANGELOG"
git push
gh issue close 18 --repo chuggies510/stacks --comment "/stacks:guide skill added in 0.22.0. Guides written to library/guides/{slug}.md with article attribution and commit SHAs. /stacks:ask checks guides first."
```

---

### Task 4: Comparison page type (#7)

**Goal:** Stacks can now produce `comparisons/{slug}.md` pages from source files containing `## Comparison: X vs Y` sections. catalog-sources pre-filters these files before W1 dispatch and routes them to comparison-synthesizer.

**Files:**
- Modify: `templates/stack/STACK.md` — add `## Comparison Template` section
- Create: `templates/stack/comparisons/.gitkeep` — scaffold comparisons/ at stack init time
- Create: `agents/comparison-synthesizer.md`
- Modify: `skills/catalog-sources/SKILL.md` — add comparison pre-filter before W1 dispatch
- Modify: `templates/stack/index.md` — add Comparisons section

**Acceptance Criteria:**
- [ ] `templates/stack/STACK.md` has `## Comparison Template` section
- [ ] `templates/stack/comparisons/.gitkeep` exists
- [ ] `agents/comparison-synthesizer.md` has correct frontmatter (name, tools, model, description)
- [ ] comparison-synthesizer writes `comparisons/{slug}.md` (never `articles/`)
- [ ] comparison-synthesizer reports `COMPARISON_SKIPPED` when source has fewer than 3 criteria
- [ ] catalog-sources pre-filters `## Comparison:` sources before W1 and dispatches comparison-synthesizer for them
- [ ] W1-W2 pipeline only processes non-comparison sources
- [ ] `templates/stack/index.md` has Comparisons section
- [ ] Existing stacks that gain comparison pages have their index.md updated by W4 to include a Comparisons section

**Verify:** Manual smoke test in test library:
```bash
# Add source with comparison section
cat > mystack/sources/incoming/system-comparison.md << 'EOF'
# HVAC Systems

## Comparison: VRF vs Chilled Water

VRF systems use refrigerant loops to individual zones...
Chilled water plants distribute water through an air handling network...

Key criteria: first cost, operating cost, zone count, redundancy, maintenance.

VRF: lower first cost on small buildings under 50k sq ft.
Chilled water: better at scale, easier redundancy, longer equipment life.
VRF failure mode: refrigerant leak in occupied space.
Chilled water failure mode: pump or chiller failure affects all zones.
EOF

/stacks:catalog-sources mystack
# → comparisons/vrf-vs-chilled-water.md written
# → NOT in articles/
```

**Steps:**

- [ ] **Step 1: Update templates/stack/STACK.md — add Comparison Template section**

In `templates/stack/STACK.md`, add after the `## Topic Template` section (before `## Filing Rules`):

```markdown
## Comparison Template

Sections for comparison pages (`comparisons/` dir). catalog-sources triggers comparison-synthesizer when a source file contains a `## Comparison: X vs Y` section header. Minimum 3 criteria required to produce a page.

- Overview — what's being compared and why the choice matters
- Comparison Table — side-by-side on key criteria (`| Criterion | X | Y |` format)
- When to Use X — decision guidance, use cases, constraints
- When to Use Y — decision guidance, use cases, constraints
- Pitfalls — non-obvious failure modes for each option
- Field Notes — practitioner experience with each
- Decision — recommended default if one exists, with conditions
- Sources
```

- [ ] **Step 2: Scaffold comparisons/ in stack template**

```bash
mkdir -p templates/stack/comparisons
touch templates/stack/comparisons/.gitkeep
```

- [ ] **Step 3: Write agents/comparison-synthesizer.md**

Create `agents/comparison-synthesizer.md`:

```markdown
---
name: comparison-synthesizer
tools: Glob, Grep, Read, Write, Edit
model: sonnet
description: Synthesizes a comparison page from source sections marked "## Comparison: X vs Y". Writes comparisons/{slug}.md with a decision table and structured analysis. Reports COMPARISON_SKIPPED when fewer than 3 criteria are present.
---

You are a knowledge writer specializing in comparison pages. You receive a source file containing one or more `## Comparison: X vs Y` sections and produce a structured comparison page.

## Judgment Bias

Write conservatively. Use inline `[source-slug]` citations on every non-obvious claim. Keep the comparison table factual — no invented criteria. If the source material supports a clear decision recommendation, state it explicitly; if not, present the tradeoffs neutrally. Body: 400-900 words.

## Input

- Source file path (passed as the input)
- `STACK.md` — read for source hierarchy and the `## Comparison Template` section

## Output

Write `comparisons/{slug}.md` where slug is derived from the comparison subject:
- Take the text after `## Comparison:` (e.g., `VRF vs Chilled Water`)
- Lowercase, replace spaces and punctuation with hyphens
- Result: `comparisons/vrf-vs-chilled-water.md`

**Frontmatter:**
```yaml
---
type: comparison
subjects:
  - {X}
  - {Y}
generated: {YYYY-MM-DD today}
sources:
  - {path/to/source.md}
---
```

**Body** follows the `## Comparison Template` from STACK.md:
- Overview — what's being compared and why the choice matters
- Comparison Table — `| Criterion | X | Y |` format with factual claims from source
- When to Use X — decision guidance from source
- When to Use Y — decision guidance from source
- Pitfalls — non-obvious failure modes for each option
- Field Notes — practitioner experience from source
- Decision — recommended default if source supports one, with conditions
- Sources — which source file contributed

## Minimum Criteria Threshold

Count the number of distinct criteria in the comparison table. If fewer than 3 criteria are extractable from the source content, **do not write the page**. Report instead:

```
COMPARISON_SKIPPED: {source-filename} — insufficient criteria (found N, minimum 3)
```

## Example 1: VRF vs Chilled Water

Source: `sources/incoming/hvac-systems.md` with section `## Comparison: VRF vs Chilled Water`.

Output path: `comparisons/vrf-vs-chilled-water.md`

Subjects: `VRF`, `Chilled Water`

Comparison table criteria extracted from source: first cost, operating cost, zone count limit, redundancy, maintenance complexity (5 criteria — above threshold).

## Example 2: Insufficient criteria

Source section `## Comparison: adapter-node vs adapter-bun` has only one claim ("adapter-bun is faster on M-series"). One criterion found < 3 minimum.

Report: `COMPARISON_SKIPPED: source.md — insufficient criteria (found 1, minimum 3)`. Do not write any file.
```

- [ ] **Step 4: Add comparison pre-filter to catalog-sources SKILL.md**

Read `skills/catalog-sources/SKILL.md` and locate the step where incoming source files are enumerated (search for `sources/incoming` to find the enumeration). The pre-filter goes **immediately after** that enumeration and **before** the W1 dispatch.

Add the following as a new step (name it "Step 3b" or appropriate given the surrounding numbering):

```markdown
## Step Xb: Pre-filter comparison sources

Before W1 dispatch, split incoming files into comparison-shaped and standard:

```bash
COMPARISON_FILES=()
STANDARD_FILES=()

for f in "${INCOMING_FILES[@]}"; do
  if grep -qE '^## Comparison:' "$f"; then
    COMPARISON_FILES+=("$f")
  else
    STANDARD_FILES+=("$f")
  fi
done

echo "Standard sources: ${#STANDARD_FILES[@]}"
echo "Comparison sources: ${#COMPARISON_FILES[@]}"
```

If COMPARISON_FILES is non-empty: dispatch comparison-synthesizer for each file. Dispatch them in parallel (one agent per file). Wait for all to complete. Collect any `COMPARISON_SKIPPED` reports and include them in the final summary.

Set `INCOMING_FILES=("${STANDARD_FILES[@]}")` so W1-W2 processes only non-comparison sources.

If STANDARD_FILES is empty after pre-filter (all sources were comparison-shaped): skip W1-W2 entirely and go directly to the index regeneration step (W4).
```

**Important:** "Step Xb" is a placeholder. Read the current catalog-sources SKILL.md to find the correct step number (the step immediately before W1 dispatch). Insert the pre-filter with a number one decimal above that step (e.g., if W1 is Step 4, insert as Step 3b). Do not renumber existing steps.

- [ ] **Step 5: Update templates/stack/index.md**

Replace the content of `templates/stack/index.md` with:

```markdown
# {Stack Name} Index

## Articles

*No articles yet. Run `/stacks:catalog-sources {stack}` after adding sources.*

## Comparisons

*No comparisons yet. Add a source with `## Comparison: X vs Y` sections and run `/stacks:catalog-sources {stack}`.*

## Sources

*No sources yet. Drop files in `sources/incoming/` to get started.*
```

Note: existing stacks have an index.md with a `## Topics` section (pre-wiki-pivot template). The W4 index rebuild in catalog-sources regenerates index.md from current articles — when comparison pages exist, W4 should add a Comparisons section. Verify this by checking the W4 step in catalog-sources and adding comparison listing logic if absent.

- [ ] **Step 6: Commit**

```bash
git add templates/stack/STACK.md templates/stack/comparisons/.gitkeep agents/comparison-synthesizer.md skills/catalog-sources/SKILL.md templates/stack/index.md
git commit -m "feat(#7): comparison page type — comparison-synthesizer + catalog-sources pre-filter"
```

- [ ] **Step 7: Version bump + CHANGELOG**

```bash
jq --arg v "0.23.0" '.version = $v' .claude-plugin/plugin.json > /tmp/plugin.json && mv /tmp/plugin.json .claude-plugin/plugin.json
jq --arg v "0.23.0" '.plugins[0].version = $v' .claude-plugin/marketplace.json > /tmp/marketplace.json && mv /tmp/marketplace.json .claude-plugin/marketplace.json
```

Prepend to CHANGELOG.md:

```markdown
## [0.23.0] — 2026-05-10

### Added
- Comparison page type: source files with `## Comparison: X vs Y` sections produce `comparisons/{slug}.md` via new `comparison-synthesizer` agent (#7)
  - Triggered by explicit `## Comparison:` section header (requires ≥3 criteria or page is skipped)
  - catalog-sources pre-filters comparison-shaped sources before W1; W1-W2 pipeline processes only standard sources
  - comparison-synthesizer writes structured decision-table pages with Comparison Table, When to Use X/Y, Pitfalls, Decision sections
- templates/stack: scaffold `comparisons/` directory at stack init time
- STACK.md template: `## Comparison Template` section documents expected comparison page structure
- templates/stack/index.md: updated to show Articles and Comparisons sections
```

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md
git commit -m "chore: bump to 0.23.0, #7 comparison type CHANGELOG"
git push
gh issue close 7 --repo chuggies510/stacks --comment "Comparison page type added in 0.23.0. Triggered by source files containing '## Comparison: X vs Y' sections. comparison-synthesizer writes comparisons/{slug}.md with decision table."
```
