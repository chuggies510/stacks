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

**Acceptance Criteria:**
- [ ] Files with specific, non-obvious technical facts route to stack incoming/ as normal
- [ ] Files with only generic content (process wisdom, meeting notes, API restatements) move to recycling-bin/
- [ ] recycling-bin/ is created lazily in process-inbox when first needed (`mkdir -p` in quality gate block)
- [ ] Step 6 report includes "Recycled (N):" section when any files are recycled (omitted when empty, matching existing pattern)
- [ ] Commit guard updated: skip commit only when BOTH MOVED and RECYCLED are empty

**Verify:** Manual smoke test in a test library — add a low-quality file ("meeting summary, no technical facts") and a high-quality file ("specific failure mode with cause and symptom"), run `/stacks:process-inbox`, confirm high-quality file routes to stack incoming/ and low-quality file moves to recycling-bin/.

**Steps:**

- [ ] **Step 1: Update process-inbox SKILL.md Step 4 — add RECYCLED list and quality gate**

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

Update the commit block to cover three cases:

- MOVED=0 and RECYCLED=0: skip the commit entirely (no changes).
- MOVED>0 and RECYCLED=0: original commit (no recycling-bin/ in staged paths).
- MOVED>0 and RECYCLED>0:
```bash
cd "$LIBRARY"
git add -A inbox/ {each affected stack}/sources/incoming/ recycling-bin/
git commit -m "chore(inbox): route {N_MOVED} file(s), recycle {N_RECYCLED} low-quality file(s)"
```
- MOVED=0 and RECYCLED>0 (all files low quality):
```bash
cd "$LIBRARY"
git add -A inbox/ recycling-bin/
git commit -m "chore(inbox): recycle {N_RECYCLED} low-quality file(s)"
```

- [ ] **Step 4: Update Step 6 report to include Recycled section**

In Step 6 of process-inbox SKILL.md, add after the Tied section:

```
Recycled — moved to recycling-bin/ (N):
  {filename}  (low quality: no specific technical facts found)
```

Omit this section if RECYCLED is empty, matching the existing pattern for Unmatched and Tied.

- [ ] **Step 5: Commit**

```bash
git add skills/process-inbox/SKILL.md
git commit -m "feat(#40): quality gate in process-inbox — low-quality files to recycling-bin"
```

- [ ] **Step 6: Close issue** *(version bump is consolidated at end of Task 4)*

```bash
gh issue close 40 --repo chuggies510/stacks --comment "Quality gate added to process-inbox in 0.20.0. Low-quality files route to recycling-bin/ instead of stack incoming dirs."
```

---

### Task 2: Scheduled loop — process-inbox + catalog-sources on a timer (#14)

**Goal:** `scripts/loop.sh` delegates inbox routing to `/stacks:process-inbox` via `claude -p`, then invokes `/stacks:catalog-sources` for each stack that has files in incoming/ after routing. Enable/disable via `$LIBRARY/.loop-enabled` sentinel. Bats tests cover mechanical logic; the `claude -p` calls are mocked.

**Files:**
- Create: `scripts/loop.sh`
- Create: `tests/loop.bats`

**Acceptance Criteria:**
- [ ] Script exits 0 when `$LIBRARY/.loop-enabled` is absent (disabled, no-op, logs "disabled")
- [ ] Script exits 0 when inbox is empty (logs timestamp + "inbox empty")
- [ ] Script invokes `claude -p "/stacks:process-inbox"` to route inbox files (delegation — no keyword routing in loop.sh)
- [ ] Script invokes `claude -p "/stacks:catalog-sources {stack}"` for each stack with files in incoming/ after process-inbox
- [ ] Script skips catalog-sources when no stacks have incoming files
- [ ] All activity appended to `$LIBRARY/loop.log` with ISO-8601 timestamps
- [ ] `bats tests/loop.bats` passes (all 6 tests)
- [ ] Script uses `STACKS_CONFIG` env var override for testability (falls back to `~/.config/stacks/config.json`)

**Verify:** `bats tests/loop.bats` → all 6 tests pass. Manual smoke test: `touch $LIBRARY/.loop-enabled && bash scripts/loop.sh` from a library with one inbox file → process-inbox invoked, loop.log written.

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
  printf '# My Stack\n\n## Scope\n\nCovers svelte, reactivity, components, runes.\n' \
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

@test "calls claude process-inbox when inbox has files" {
  touch "$TEST_TMP/lib/.loop-enabled"
  touch "$TEST_TMP/lib/inbox/file.md"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "process-inbox" "$TEST_TMP/claude-calls.log"
}

@test "calls claude catalog-sources for stacks with files in incoming/" {
  touch "$TEST_TMP/lib/.loop-enabled"
  touch "$TEST_TMP/lib/inbox/file.md"
  # Pre-populate incoming/ to simulate what process-inbox would have done
  touch "$TEST_TMP/lib/mystack/sources/incoming/filed.md"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "catalog-sources mystack" "$TEST_TMP/claude-calls.log"
}
```

Run: `bats tests/loop.bats` → expected: all 6 fail (script doesn't exist yet).

- [ ] **Step 2: Write scripts/loop.sh**

```bash
#!/usr/bin/env bash
# Scheduled library maintenance: run process-inbox then catalog stacks with pending files.
#
# Add to crontab (crontab -e):
#   0 * * * * PATH="$HOME/.local/bin:$HOME/.nvm/default/bin:/usr/local/bin:$PATH" \
#             bash /path/to/stacks/scripts/loop.sh
#
# Enable for a library:  touch "$LIBRARY/.loop-enabled"
# Disable:               rm "$LIBRARY/.loop-enabled"
#
# Note: 'claude' must be in PATH at cron time (see crontab PATH line above).
set -euo pipefail

CONFIG="${STACKS_CONFIG:-$HOME/.config/stacks/config.json}"
[[ -f "$CONFIG" ]] || { echo "[loop] no config at $CONFIG"; exit 0; }

LIBRARY=$(jq -r '.library // empty' "$CONFIG")
LIBRARY="${LIBRARY/#\~/$HOME}"
[[ -d "$LIBRARY" ]] || { echo "[loop] library not found: $LIBRARY"; exit 0; }

LOG="$LIBRARY/loop.log"
log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG"; }

[[ -f "$LIBRARY/.loop-enabled" ]] || { log "disabled (.loop-enabled absent)"; exit 0; }

mapfile -t inbox_files < <(find "$LIBRARY/inbox" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)
if [[ ${#inbox_files[@]} -eq 0 ]]; then
  log "inbox empty — no-op"
  exit 0
fi

log "routing ${#inbox_files[@]} inbox file(s) via process-inbox..."
cd "$LIBRARY"
claude -p "/stacks:process-inbox" >> "$LOG" 2>&1 \
  || log "process-inbox failed (see log above)"

cataloged=0
for stack_dir in "$LIBRARY"/*/; do
  [[ -f "${stack_dir}STACK.md" ]] || continue
  stack=$(basename "$stack_dir")
  count=$(find "${stack_dir}sources/incoming" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$count" -gt 0 ]]; then
    log "cataloging $stack ($count file(s))..."
    claude -p "/stacks:catalog-sources $stack" >> "$LOG" 2>&1 \
      || log "catalog-sources failed for $stack (see log above)"
    cataloged=$((cataloged + 1))
  fi
done

[[ "$cataloged" -eq 0 ]] && log "no stacks with incoming files after routing"
log "done"
```

- [ ] **Step 3: Run tests**

```bash
bats tests/loop.bats
```

Expected: all 6 tests pass.

- [ ] **Step 4: Commit**

```bash
git add scripts/loop.sh tests/loop.bats
git commit -m "feat(#14): scheduled loop — process-inbox routing + catalog-sources per stack"
```

- [ ] **Step 5: Close issue** *(version bump is consolidated at end of Task 4)*

```bash
gh issue close 14 --repo chuggies510/stacks --comment "Scheduled loop script added in 0.20.0 (scripts/loop.sh). Delegates inbox routing to /stacks:process-inbox via claude -p; catalogs any stacks with pending incoming files after routing. Enable with touch \$LIBRARY/.loop-enabled."
```

---

### Task 3: /stacks:guide on-demand synthesis (#18)

**Goal:** New `/stacks:guide "{topic}"` skill retrieves relevant articles across stacks and synthesizes a structured long-form guide, writing it to `$LIBRARY/guides/{slug}.md`. `/stacks:ask` surfaces existing guides before doing article retrieval.

**Files:**
- Create: `skills/guide/SKILL.md`
- Modify: `skills/ask/SKILL.md` — add Step 1.5 to check existing guides before article retrieval

**Acceptance Criteria:**
- [ ] `skills/guide/SKILL.md` exists with correct frontmatter (name, description)
- [ ] Guide written to `$LIBRARY/guides/{slug}.md` with frontmatter: topic, generated, stacks, articles (with commit SHAs), excluded
- [ ] `--stacks` flag scopes retrieval to named stacks (same comma-separated format as /stacks:ask)
- [ ] `--regenerate` flag bypasses existing guide check and overwrites
- [ ] Guide body: 800-2000 words, structured sections (Overview, Key Concepts, Patterns, Pitfalls, Field Notes, Sources)
- [ ] `/stacks:ask` Step 1.5 checks `$LIBRARY/guides/` before article retrieval and surfaces matching guide

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

- [ ] **Step 1: Write skills/guide/SKILL.md**

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

- [ ] **Step 2: Update skills/ask/SKILL.md — add Step 1.5 guide check**

In `skills/ask/SKILL.md`, add a new `## Step 1.5: Check existing guides` section immediately after `## Step 1: Find the library` and before `## Step 2: Read the catalog`.

Content of the new step:

```markdown
## Step 1.5: Check existing guides

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

- [ ] **Step 3: Commit**

```bash
git add skills/guide/SKILL.md skills/ask/SKILL.md
git commit -m "feat(#18): /stacks:guide on-demand synthesis + ask guide-first check"
```

- [ ] **Step 4: Close issue** *(version bump is consolidated at end of Task 4)*

```bash
gh issue close 18 --repo chuggies510/stacks --comment "/stacks:guide skill added in 0.20.0. Guides written to library/guides/{slug}.md with article attribution and commit SHAs. /stacks:ask checks guides/ first (Step 1.5)."
```

---

### Task 4: Comparison page type (#7)

**Goal:** Stacks can now produce `comparisons/{slug}.md` pages from source files containing `## Comparison: X vs Y` sections. catalog-sources pre-filters these files before W1 dispatch and routes them to comparison-synthesizer.

**Files:**
- Modify: `templates/stack/STACK.md` — add `## Comparison Template` section
- Create: `agents/comparison-synthesizer.md`
- Modify: `skills/catalog-sources/SKILL.md` — add comparison pre-filter (Step 4.5) before W1 dispatch
- Modify: `scripts/regenerate-moc.sh` — add Comparisons section to W4 index rebuild
- Modify: `templates/stack/index.md` — add Comparisons section

**Acceptance Criteria:**
- [ ] `templates/stack/STACK.md` has `## Comparison Template` section
- [ ] `agents/comparison-synthesizer.md` has correct frontmatter (name, tools, model, description)
- [ ] comparison-synthesizer writes `comparisons/{slug}.md` (never `articles/`)
- [ ] comparison-synthesizer reports `COMPARISON_SKIPPED` when source has fewer than 3 criteria
- [ ] catalog-sources Step 4.5 pre-filters `## Comparison:` sources before W1 and dispatches comparison-synthesizer for them
- [ ] W1-W2 pipeline only processes non-comparison sources (`NEW_SOURCES_ARR` reassigned after split)
- [ ] `scripts/regenerate-moc.sh` updated to emit a Comparisons section in index.md when comparisons/ has pages
- [ ] `templates/stack/index.md` has Comparisons section

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

- [ ] **Step 2: Write agents/comparison-synthesizer.md**

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

## Example 3: Exactly 3 criteria — page produced

Source section `## Comparison: SQLite vs Postgres` contains exactly 3 extractable criteria: setup complexity, concurrent write behavior, and backup approach.

Output path: `comparisons/sqlite-vs-postgres.md`

3 criteria meets the minimum threshold — produce the page. Comparison table has 3 rows. Decision section: "SQLite for single-process apps, Postgres for concurrent writers."
```

- [ ] **Step 3: Add comparison pre-filter to catalog-sources SKILL.md**

Read `skills/catalog-sources/SKILL.md` and locate the step where `NEW_SOURCES_ARR` is built (search for `NEW_SOURCES_ARR` to find it — this is the bash array of incoming source paths used for W1 dispatch). The pre-filter goes **immediately after** that enumeration and **before** the W1 dispatch. In the existing step numbering, this falls after Step 4 (W0 enumeration), so insert as `Step 4.5`.

Add the following new step to catalog-sources SKILL.md:

```markdown
## Step 4.5: Pre-filter comparison sources

Before W1 dispatch, split `NEW_SOURCES_ARR` into comparison-shaped and standard:

```bash
COMPARISON_FILES=()
STANDARD_FILES=()

for f in "${NEW_SOURCES_ARR[@]}"; do
  if grep -qE '^## Comparison:' "$f"; then
    COMPARISON_FILES+=("$f")
  else
    STANDARD_FILES+=("$f")
  fi
done

echo "Standard sources: ${#STANDARD_FILES[@]}"
echo "Comparison sources: ${#COMPARISON_FILES[@]}"

NEW_SOURCES_ARR=("${STANDARD_FILES[@]}")
N_SOURCES=${#NEW_SOURCES_ARR[@]}
```

If COMPARISON_FILES is non-empty: dispatch comparison-synthesizer for each file. Dispatch them in parallel (one agent per file). Wait for all to complete. Collect any `COMPARISON_SKIPPED` reports and include them in the final summary.

If STANDARD_FILES is empty after pre-filter (all sources were comparison-shaped): skip W1-W2 entirely and go directly to the index regeneration step (W4).
```

- [ ] **Step 4: Update templates/stack/index.md**

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

Note: existing stacks have an index.md with a `## Topics` section (pre-wiki-pivot template). The W4 index rebuild regenerates index.md — Step 5 adds Comparisons section support to that rebuild script.

- [ ] **Step 5: Update scripts/regenerate-moc.sh — add Comparisons section**

Read `scripts/regenerate-moc.sh`. This script is invoked at W4 to rebuild each stack's `index.md`. Find the block that writes the `## Articles` section. Immediately after that block (before the `## Sources` section), add logic to emit a `## Comparisons` section when `comparisons/*.md` files exist:

```bash
# After the Articles section is written, before Sources section:
comparison_pages=$(find "$STACK_DIR/comparisons" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)
if [[ -n "$comparison_pages" ]]; then
  echo "" >> "$INDEX"
  echo "## Comparisons" >> "$INDEX"
  echo "" >> "$INDEX"
  while IFS= read -r page; do
    slug=$(basename "$page" .md)
    title=$(awk '/^title:/{gsub(/^title: /, ""); print; exit}' "$page" 2>/dev/null || echo "$slug")
    echo "- [$title](comparisons/${slug}.md)" >> "$INDEX"
  done <<< "$comparison_pages"
fi
```

Read the actual script first to confirm variable names (`$STACK_DIR`, `$INDEX`, etc.) and adapt the snippet to match. If the script uses different variable names, substitute accordingly.

- [ ] **Step 6: Commit**

```bash
git add templates/stack/STACK.md agents/comparison-synthesizer.md skills/catalog-sources/SKILL.md scripts/regenerate-moc.sh templates/stack/index.md
git commit -m "feat(#7): comparison page type — comparison-synthesizer + catalog-sources pre-filter"
```

- [ ] **Step 7: Consolidated version bump + CHANGELOG (all 4 tasks)**

This is the single version bump for the entire Phase 3+4 batch (#40 + #14 + #18 + #7):

```bash
jq --arg v "0.20.0" '.version = $v' .claude-plugin/plugin.json > /tmp/plugin.json && mv /tmp/plugin.json .claude-plugin/plugin.json
jq --arg v "0.20.0" '.plugins[0].version = $v' .claude-plugin/marketplace.json > /tmp/marketplace.json && mv /tmp/marketplace.json .claude-plugin/marketplace.json
```

Prepend to CHANGELOG.md:

```markdown
## [0.20.0] — 2026-05-10

### Added
- process-inbox: quality gate — low-quality files route to `library/recycling-bin/` instead of stack incoming dirs. Assessed by reading file body content. Step 6 report includes Recycled section when files are recycled. (#40)
- scripts/loop.sh: scheduled library maintenance — delegates inbox routing to `/stacks:process-inbox` via `claude -p`, then catalogs stacks with pending incoming files. Enable with `touch $LIBRARY/.loop-enabled`. Add to crontab with explicit PATH including claude's install dir. (#14)
- /stacks:guide: new skill — synthesizes long-form guide (800-2000 words) from library articles. Writes to `library/guides/{slug}.md` with full article attribution and commit SHAs. `--stacks` scopes to named stacks; `--regenerate` rebuilds from current articles. (#18)
- /stacks:ask: checks `library/guides/` before article retrieval (Step 1.5) and surfaces existing guide. (#18)
- Comparison page type: source files with `## Comparison: X vs Y` sections produce `comparisons/{slug}.md` via new `comparison-synthesizer` agent. Requires ≥3 criteria or page is skipped with `COMPARISON_SKIPPED` report. catalog-sources Step 4.5 pre-filters before W1; W1-W2 processes only standard sources. W4 index rebuild now includes Comparisons section. (#7)
- STACK.md template: `## Comparison Template` section documents expected comparison page structure.
- templates/stack/index.md: updated to show Articles and Comparisons sections.
```

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md
git commit -m "chore: bump to 0.20.0, Phase 3+4 CHANGELOG (#40 #14 #18 #7)"
git push
gh issue close 7 --repo chuggies510/stacks --comment "Comparison page type added in 0.20.0. Triggered by source files containing '## Comparison: X vs Y' sections. comparison-synthesizer writes comparisons/{slug}.md with decision table."
```
