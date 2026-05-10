# Stacks Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close #50 (pipeline content-structure gates) and #5 (cross-stack lookup for /stacks:ask), unblocking Phase 4 (#18, #7).

**Architecture:** #50 adds a new `assert-structure.sh` script that runs content-shape checks after `assert-written.sh` passes mtime checks; call sites land in `catalog-sources` (W1, W1b, W2) and `audit-stack` (A1, A2). #5 extends `skills/ask/SKILL.md` with `--stack`/`--stacks` flags, defaults to cross-stack search when neither is set, and structures the retrieval section as a named stub boundary for when #10 (qmd) replaces it.

**Tech Stack:** Bash, bats (tests), SKILL.md natural-language instructions

---

## Issues closed

- #50: pipeline gates check file recency but not content structure
- #5: cross-stack lookup for /stacks:ask

---

### Task 1: Write assert-structure.sh with bats tests

**Goal:** A standalone `scripts/assert-structure.sh` that checks content shape for each known file type, with a bats test suite covering all types and error paths.

**Files:**
- Create: `scripts/assert-structure.sh`
- Create: `tests/assert-structure.bats`

**Acceptance Criteria:**
- [ ] Script exits 0 when the file matches the named type
- [ ] Script exits 1 and prints `STRUCTURE_FAILURE:` to stderr on mismatch for each type
- [ ] Script exits 1 on unknown type
- [ ] All 7 types covered: `concept-batch`, `dedup-md`, `dedup-meta`, `article-md`, `article-validated`, `glossary-md`, `invariants-md`
- [ ] bats suite passes: `bats tests/assert-structure.bats`

**Verify:** `bats tests/assert-structure.bats` → all tests pass, zero failures

**Steps:**

- [ ] **Step 1: Create the tests directory and write the bats test file**

```bash
mkdir -p tests
```

Write `tests/assert-structure.bats`:

```bash
#!/usr/bin/env bats

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/assert-structure.sh"
TMPDIR_TEST="$(mktemp -d)"

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# --- concept-batch ---
@test "concept-batch: passes with Concept block" {
  echo -e "## Concept: foo\nslug: foo\n\n### Claims\n- bar" > "$TMPDIR_TEST/batch.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/batch.md" concept-batch agent1
  [ "$status" -eq 0 ]
}

@test "concept-batch: fails when no Concept block" {
  echo "# just a header" > "$TMPDIR_TEST/batch.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/batch.md" concept-batch agent1
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

# --- dedup-md ---
@test "dedup-md: passes with Concept block" {
  echo -e "## Concept: bar\nslug: bar" > "$TMPDIR_TEST/dedup.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/dedup.md" dedup-md agent1
  [ "$status" -eq 0 ]
}

@test "dedup-md: fails when no Concept block" {
  echo "empty" > "$TMPDIR_TEST/dedup.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/dedup.md" dedup-md agent1
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

# --- dedup-meta ---
@test "dedup-meta: passes with populated ALL_SLUGS" {
  echo "ALL_SLUGS=foo bar baz" > "$TMPDIR_TEST/meta.txt"
  run bash "$SCRIPT" "$TMPDIR_TEST/meta.txt" dedup-meta agent1
  [ "$status" -eq 0 ]
}

@test "dedup-meta: fails when ALL_SLUGS missing" {
  echo "N_CONCEPTS=3" > "$TMPDIR_TEST/meta.txt"
  run bash "$SCRIPT" "$TMPDIR_TEST/meta.txt" dedup-meta agent1
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

@test "dedup-meta: fails when ALL_SLUGS is empty" {
  echo "ALL_SLUGS=" > "$TMPDIR_TEST/meta.txt"
  run bash "$SCRIPT" "$TMPDIR_TEST/meta.txt" dedup-meta agent1
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

# --- article-md ---
@test "article-md: passes with all required frontmatter keys" {
  printf -- '---\nextraction_hash: abc\ntitle: Foo\nslug: foo\n---\nBody.\n' > "$TMPDIR_TEST/article.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/article.md" article-md agent1
  [ "$status" -eq 0 ]
}

@test "article-md: fails when extraction_hash missing" {
  printf -- '---\ntitle: Foo\nslug: foo\n---\nBody.\n' > "$TMPDIR_TEST/article.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/article.md" article-md agent1
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

@test "article-md: fails when title missing" {
  printf -- '---\nextraction_hash: abc\nslug: foo\n---\nBody.\n' > "$TMPDIR_TEST/article.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/article.md" article-md agent1
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

@test "article-md: fails when slug missing" {
  printf -- '---\nextraction_hash: abc\ntitle: Foo\n---\nBody.\n' > "$TMPDIR_TEST/article.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/article.md" article-md agent1
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

# --- article-validated ---
@test "article-validated: passes with VERIFIED mark" {
  echo "Some claim. [VERIFIED]" > "$TMPDIR_TEST/av.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/av.md" article-validated agent1
  [ "$status" -eq 0 ]
}

@test "article-validated: passes with DRIFT mark" {
  echo "Some claim. [DRIFT]" > "$TMPDIR_TEST/av.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/av.md" article-validated agent1
  [ "$status" -eq 0 ]
}

@test "article-validated: passes with UNSOURCED mark" {
  echo "Some claim. [UNSOURCED]" > "$TMPDIR_TEST/av.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/av.md" article-validated agent1
  [ "$status" -eq 0 ]
}

@test "article-validated: passes with STALE mark" {
  echo "Some claim. [STALE]" > "$TMPDIR_TEST/av.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/av.md" article-validated agent1
  [ "$status" -eq 0 ]
}

@test "article-validated: fails with no marks" {
  echo "Some claim with no mark." > "$TMPDIR_TEST/av.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/av.md" article-validated agent1
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

# --- glossary-md ---
@test "glossary-md: passes with bold term entry" {
  echo "**Approach temperature**: The delta between leaving water temp and wet-bulb. (from: cooling-towers)" > "$TMPDIR_TEST/glossary.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/glossary.md" glossary-md agent1
  [ "$status" -eq 0 ]
}

@test "glossary-md: fails when no bold term entries" {
  echo "# Glossary" > "$TMPDIR_TEST/glossary.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/glossary.md" glossary-md agent1
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

# --- invariants-md ---
@test "invariants-md: passes with numbered entry" {
  printf '1. Raising chilled water setpoint reduces compressor energy.\n   appears-in: art-a, art-b\n' > "$TMPDIR_TEST/invariants.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/invariants.md" invariants-md agent1
  [ "$status" -eq 0 ]
}

@test "invariants-md: fails with no numbered entries" {
  echo "# Invariants" > "$TMPDIR_TEST/invariants.md"
  run bash "$SCRIPT" "$TMPDIR_TEST/invariants.md" invariants-md agent1
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}

# --- unknown type ---
@test "unknown type: exits 1" {
  echo "content" > "$TMPDIR_TEST/file.txt"
  run bash "$SCRIPT" "$TMPDIR_TEST/file.txt" unknown-type agent1
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRUCTURE_FAILURE"* ]]
}
```

- [ ] **Step 2: Run tests — expect all to fail (no script yet)**

```bash
bats tests/assert-structure.bats 2>&1 | head -20
```

Expected: failures with "No such file or directory" for the script path.

- [ ] **Step 3: Write assert-structure.sh**

Write `scripts/assert-structure.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

path=$1
type=$2
agent_label=${3:-unknown}

fail() {
  echo "STRUCTURE_FAILURE: $1: $path (agent=$agent_label)" >&2
  exit 1
}

case "$type" in
  concept-batch|dedup-md)
    grep -q "^## Concept:" "$path" || fail "no '## Concept:' block found"
    ;;
  dedup-meta)
    grep -q "^ALL_SLUGS=" "$path" || fail "missing ALL_SLUGS= line"
    grep -q "^ALL_SLUGS=.\+" "$path" || fail "ALL_SLUGS is empty"
    ;;
  article-md)
    for key in extraction_hash title slug; do
      grep -q "^${key}:" "$path" || fail "missing frontmatter key '${key}'"
    done
    ;;
  article-validated)
    grep -qE '\[(VERIFIED|DRIFT|UNSOURCED|STALE)\]' "$path" \
      || fail "no validation marks found (expected VERIFIED, DRIFT, UNSOURCED, or STALE)"
    ;;
  glossary-md)
    grep -q "^\*\*" "$path" || fail "no bold term entries found (expected '**Term**: ...' format)"
    ;;
  invariants-md)
    grep -qE "^[0-9]+\." "$path" || fail "no numbered entries found (expected '1. rule...' format)"
    ;;
  *)
    fail "unknown structure type '$type'"
    ;;
esac
```

```bash
chmod +x scripts/assert-structure.sh
```

- [ ] **Step 4: Run tests — expect all to pass**

```bash
bats tests/assert-structure.bats
```

Expected: all tests pass, output ends with `N tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add scripts/assert-structure.sh tests/assert-structure.bats
git commit -m "feat(#50): add assert-structure.sh with bats test suite"
```

---

### Task 2: Add structure gates to catalog-sources

**Goal:** The catalog-sources SKILL.md calls `assert-structure.sh` at W1, W1b, and W2, so a truncated batch file, empty dedup, or missing article frontmatter halts the pipeline immediately rather than silently propagating.

**Files:**
- Modify: `skills/catalog-sources/SKILL.md`

**Acceptance Criteria:**
- [ ] W1 gate calls `assert-structure.sh` with type `concept-batch` after each `assert-written.sh` call
- [ ] W1b gate calls `assert-structure.sh` with type `dedup-md` on `_dedup.md` after the dedup Python pass
- [ ] W1b gate calls `assert-structure.sh` with type `dedup-meta` on `_dedup-meta.txt` after the dedup Python pass
- [ ] W2 gate calls `assert-structure.sh` with type `article-md` after each `assert-written.sh` call
- [ ] Structure failures produce `STRUCTURE_FAILURE:` in the same error surface as `AGENT_WRITE_FAILURE:` (stderr, halt with exit 1)

**Verify:** Read the modified SKILL.md and confirm all 5 call sites are present and use `"$SCRIPTS_DIR/assert-structure.sh"` with the correct type argument.

**Steps:**

- [ ] **Step 1: Read the current W1 gate block in catalog-sources SKILL.md**

Read `skills/catalog-sources/SKILL.md` lines 240-255 (the W1 assert-written loop).

The block currently looks like:
```bash
  PARTIAL="$STACK/dev/extractions/batch-${i}-concepts.md"
  if ! "$SCRIPTS_DIR/assert-written.sh" "$PARTIAL" "$DISPATCH_EPOCH_W1" "concept-identifier" 2>/dev/null; then
    W1_FAILED+=("batch-${i}")
  fi
```

- [ ] **Step 2: Add assert-structure.sh call at W1 gate**

In `skills/catalog-sources/SKILL.md`, locate the W1 assert-written block and extend it. The new block:

```bash
  PARTIAL="$STACK/dev/extractions/batch-${i}-concepts.md"
  if ! "$SCRIPTS_DIR/assert-written.sh" "$PARTIAL" "$DISPATCH_EPOCH_W1" "concept-identifier" 2>/dev/null; then
    W1_FAILED+=("batch-${i}")
  elif ! "$SCRIPTS_DIR/assert-structure.sh" "$PARTIAL" concept-batch "concept-identifier" 2>/dev/null; then
    W1_FAILED+=("batch-${i}")
  fi
```

Use Edit on `skills/catalog-sources/SKILL.md` to make this change. Match the exact surrounding context to avoid a collision.

- [ ] **Step 3: Read the W1b dedup block**

Read `skills/catalog-sources/SKILL.md` around lines 278-295 (the Python dedup call and the source-meta load that follows).

The block currently looks like:
```bash
DEDUP="$STACK/dev/extractions/_dedup.md"
: > "$DEDUP"
python3 "$SCRIPTS_DIR/dedup-extractions.py" "$STACK/dev/extractions" "$DEDUP"

# Load the meta into shell vars.
source <(grep -E '^[A-Z_]+=' "$STACK/dev/extractions/_dedup-meta.txt" | sed 's/^/export /')
CONCEPT_SLUGS=($ALL_SLUGS)
```

- [ ] **Step 4: Add assert-structure.sh calls at W1b gate**

After the `python3 "$SCRIPTS_DIR/dedup-extractions.py"` line and before the `source <(...)` line, add:

```bash
"$SCRIPTS_DIR/assert-structure.sh" "$DEDUP" dedup-md "dedup-extractions" \
  || { echo "STRUCTURE_FAILURE: dedup output malformed — no concept blocks"; exit 1; }
"$SCRIPTS_DIR/assert-structure.sh" "$STACK/dev/extractions/_dedup-meta.txt" dedup-meta "dedup-extractions" \
  || { echo "STRUCTURE_FAILURE: dedup meta malformed — missing or empty ALL_SLUGS"; exit 1; }
```

- [ ] **Step 5: Read the W2 assert-written block**

Read `skills/catalog-sources/SKILL.md` around line 348 (the W2 article gate per slug).

The block currently looks like:
```bash
    if ! "$SCRIPTS_DIR/assert-written.sh" "$STACK/articles/${slug}.md" "$DISPATCH_EPOCH_W2_WAVE" "article-synthesizer" 2>/dev/null; then
      W2_FAILED+=("$slug")
    fi
```

- [ ] **Step 6: Add assert-structure.sh call at W2 gate**

Extend the W2 gate block to also check article frontmatter structure:

```bash
    if ! "$SCRIPTS_DIR/assert-written.sh" "$STACK/articles/${slug}.md" "$DISPATCH_EPOCH_W2_WAVE" "article-synthesizer" 2>/dev/null; then
      W2_FAILED+=("$slug")
    elif ! "$SCRIPTS_DIR/assert-structure.sh" "$STACK/articles/${slug}.md" article-md "article-synthesizer" 2>/dev/null; then
      W2_FAILED+=("$slug")
    fi
```

- [ ] **Step 7: Verify all 5 call sites present**

```bash
grep -c "assert-structure.sh" skills/catalog-sources/SKILL.md
```

Expected: `5` (W1 elif, W1b dedup-md, W1b dedup-meta, W2 elif).

Wait — that's actually 4 calls (1 W1 + 2 W1b + 1 W2). Correct count: `4`.

```bash
grep "assert-structure.sh" skills/catalog-sources/SKILL.md
```

Confirm 4 lines, each with the correct type (`concept-batch`, `dedup-md`, `dedup-meta`, `article-md`).

- [ ] **Step 8: Commit**

```bash
git add skills/catalog-sources/SKILL.md
git commit -m "feat(#50): add assert-structure.sh gates to catalog-sources (W1, W1b, W2)"
```

---

### Task 3: Add structure gates to audit-stack

**Goal:** The audit-stack SKILL.md calls `assert-structure.sh` at A1 (validated articles) and A2 (glossary, invariants), so a validator that wrote no marks or a synthesizer that produced an empty glossary halts the pipeline.

**Files:**
- Modify: `skills/audit-stack/SKILL.md`

**Acceptance Criteria:**
- [ ] A1 gate calls `assert-structure.sh` with type `article-validated` after each article's `assert-written.sh` call
- [ ] A2 merge gate calls `assert-structure.sh` with type `glossary-md` on `$STACK/glossary.md` after the merge assert-written gate
- [ ] A2 merge gate calls `assert-structure.sh` with type `invariants-md` on `$STACK/invariants.md` after the merge assert-written gate

**Verify:** `grep "assert-structure.sh" skills/audit-stack/SKILL.md` returns 3 lines with types `article-validated`, `glossary-md`, `invariants-md`.

**Steps:**

- [ ] **Step 1: Read the A1 parent gate block**

Read `skills/audit-stack/SKILL.md` around line 161 (the per-article assert-written loop).

The block currently looks like:
```bash
    if ! "$SCRIPTS_DIR/assert-written.sh" "$article" "$DISPATCH_EPOCH" "validator-parent-gate" 2>/dev/null; then
      A1_FAILED+=("$article")
    fi
```

- [ ] **Step 2: Add assert-structure.sh at A1 gate**

Extend the A1 gate to also check for validation marks:

```bash
    if ! "$SCRIPTS_DIR/assert-written.sh" "$article" "$DISPATCH_EPOCH" "validator-parent-gate" 2>/dev/null; then
      A1_FAILED+=("$article")
    elif ! "$SCRIPTS_DIR/assert-structure.sh" "$article" article-validated "validator-parent-gate" 2>/dev/null; then
      A1_FAILED+=("$article")
    fi
```

- [ ] **Step 3: Read the A2 merge gate block**

Read `skills/audit-stack/SKILL.md` around lines 236-243 (the post-merge assert-written loop for `glossary.md`, `invariants.md`, `contradictions.md`).

The block currently looks like:
```bash
for f in glossary.md invariants.md contradictions.md; do
  if ! "$SCRIPTS_DIR/assert-written.sh" "$STACK/$f" "$DISPATCH_EPOCH" "synthesizer-merge-gate" 2>/dev/null; then
    echo "AGENT_WRITE_FAILURE: A2 stack-root $f ungated"; exit 1
  fi
done
G_TERMS=$(grep -c '^\*\*' "$STACK/glossary.md" 2>/dev/null || echo 0)
INV_COUNT=$(grep -c '^[0-9]\+\.' "$STACK/invariants.md" 2>/dev/null || echo 0)
```

- [ ] **Step 4: Add assert-structure.sh calls at A2 merge gate**

Replace the `for f in ...` block with individual gates that also check structure for `glossary.md` and `invariants.md`:

```bash
for f in glossary.md invariants.md contradictions.md; do
  if ! "$SCRIPTS_DIR/assert-written.sh" "$STACK/$f" "$DISPATCH_EPOCH" "synthesizer-merge-gate" 2>/dev/null; then
    echo "AGENT_WRITE_FAILURE: A2 stack-root $f ungated"; exit 1
  fi
done
"$SCRIPTS_DIR/assert-structure.sh" "$STACK/glossary.md" glossary-md "synthesizer-merge-gate" \
  || { echo "STRUCTURE_FAILURE: glossary.md has no bold term entries"; exit 1; }
"$SCRIPTS_DIR/assert-structure.sh" "$STACK/invariants.md" invariants-md "synthesizer-merge-gate" \
  || { echo "STRUCTURE_FAILURE: invariants.md has no numbered entries"; exit 1; }
G_TERMS=$(grep -c '^\*\*' "$STACK/glossary.md" 2>/dev/null || echo 0)
INV_COUNT=$(grep -c '^[0-9]\+\.' "$STACK/invariants.md" 2>/dev/null || echo 0)
```

- [ ] **Step 5: Verify call sites**

```bash
grep "assert-structure.sh" skills/audit-stack/SKILL.md
```

Expected: 3 lines — `article-validated`, `glossary-md`, `invariants-md`.

- [ ] **Step 6: Commit**

```bash
git add skills/audit-stack/SKILL.md
git commit -m "feat(#50): add assert-structure.sh gates to audit-stack (A1, A2)"
```

- [ ] **Step 7: Version bump and changelog**

Bump patch version in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`. Add CHANGELOG entry:

```
## [0.18.1] - 2026-05-10

### Added
- `assert-structure.sh`: content-shape gate for pipeline output files (types: concept-batch, dedup-md, dedup-meta, article-md, article-validated, glossary-md, invariants-md)
- `catalog-sources`: assert-structure gates at W1, W1b, W2
- `audit-stack`: assert-structure gates at A1, A2
- `tests/assert-structure.bats`: 20-test bats suite for assert-structure.sh

Closes #50.
```

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md
git commit -m "chore: bump to 0.18.1, add #50 to CHANGELOG"
```

---

### Task 4: Cross-stack lookup for /stacks:ask

**Goal:** `/stacks:ask` defaults to searching all stacks in the library when no `--stack` or `--stacks` flag is given. `--stack {name}` forces single-stack scope (existing behavior). `--stacks {a,b,c}` scopes to a named subset. The retrieval step is structured as a named stub for future replacement by #10 (qmd search).

**Files:**
- Modify: `skills/ask/SKILL.md`

**Acceptance Criteria:**
- [ ] `--stack {name}` parses correctly and limits retrieval to one stack
- [ ] `--stacks {a,b,c}` parses correctly and limits retrieval to the named subset
- [ ] No flag: all stacks from catalog.md are searched
- [ ] Answers cite both the article title and the stack it came from
- [ ] The article-retrieval block is labelled `## Stacks-search stub` with a `# REPLACE-WITH-QMD` comment so #10 has a clear swap point

**Verify:** Read the modified `skills/ask/SKILL.md` Step 3 and Step 5. Confirm: (a) flag parsing produces `STACKS_TO_SEARCH` (a list of stack names), (b) Step 5 article mode iterates over `STACKS_TO_SEARCH`, (c) the stub comment is present, (d) the answer format includes the stack name.

**Steps:**

- [ ] **Step 1: Read the current Step 3 (parse the query) in skills/ask/SKILL.md**

Read the full Step 3 block. It currently extracts `STACK` (first word if it matches a directory) and `QUERY`. We are replacing this logic.

- [ ] **Step 2: Rewrite Step 3 to parse flags and set STACKS_TO_SEARCH**

Replace the Step 3 block with this new version:

````markdown
## Step 3: Parse the query and resolve stack scope

`$ARGUMENTS` contains the full query text. Parse flags before extracting the query:

```bash
RAW="$ARGUMENTS"
STACK_SINGLE=""
STACKS_MULTI=""
QUERY=""

# Extract --stack {name}
if [[ "$RAW" == *"--stack "* ]]; then
  STACK_SINGLE=$(echo "$RAW" | sed 's/.*--stack[[:space:]]*//' | awk '{print $1}')
  RAW=$(echo "$RAW" | sed "s/--stack[[:space:]]*${STACK_SINGLE}//")
fi

# Extract --stacks {a,b,c}
if [[ "$RAW" == *"--stacks "* ]]; then
  STACKS_MULTI=$(echo "$RAW" | sed 's/.*--stacks[[:space:]]*//' | awk '{print $1}')
  RAW=$(echo "$RAW" | sed "s/--stacks[[:space:]]*${STACKS_MULTI}//")
fi

QUERY=$(echo "$RAW" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
```

**Resolve STACKS_TO_SEARCH** — the list of stack names to search:

- If `--stack {name}` was given: `STACKS_TO_SEARCH=("{name}")`. Validate the stack directory exists; error if not.
- If `--stacks {a,b,c}` was given: split on `,` into an array. Validate each; error on any missing.
- If neither flag: extract all stack directory names from `catalog.md` (lines matching `^- \[`) as `STACKS_TO_SEARCH`. This is the default cross-stack path.

```bash
# -- REPLACE-WITH-QMD when #10 lands: this bash enumeration is the stub.
# The qmd implementation accepts (query, stacks_to_search[]) and returns
# (article_path, stack_name, score)[] — replace Step 5 article-mode body only.
if [[ -n "$STACK_SINGLE" ]]; then
  [[ -d "$LIBRARY/$STACK_SINGLE" ]] || { echo "ERROR: stack '$STACK_SINGLE' not found"; exit 1; }
  STACKS_TO_SEARCH=("$STACK_SINGLE")
elif [[ -n "$STACKS_MULTI" ]]; then
  IFS=',' read -ra STACKS_TO_SEARCH <<< "$STACKS_MULTI"
  for s in "${STACKS_TO_SEARCH[@]}"; do
    [[ -d "$LIBRARY/$s" ]] || { echo "ERROR: stack '$s' not found"; exit 1; }
  done
else
  # Default: all stacks from catalog.md
  mapfile -t STACKS_TO_SEARCH < <(
    grep '^- \[' "$LIBRARY/catalog.md" \
    | sed 's|.*\[\([^]]*\)\](\([^/]*\)/).*|\2|'
  )
  [[ ${#STACKS_TO_SEARCH[@]} -gt 0 ]] \
    || { echo "No stacks found in catalog.md — run /stacks:new-stack first."; exit 1; }
fi
```
````

- [ ] **Step 3: Read the current Step 4 (read the stack index) and Step 5 (read topic guides)**

Read Steps 4 and 5 in `skills/ask/SKILL.md`. Step 4 reads `$LIBRARY/{stack}/index.md` and matches the query against topics. Step 5 branches on article vs guide mode.

- [ ] **Step 4: Rewrite Steps 4 and 5 for multi-stack retrieval**

Replace Step 4 header and body with:

````markdown
## Step 4: Read indexes for all stacks in scope

For each stack in `STACKS_TO_SEARCH`:
- Read `$LIBRARY/{stack}/index.md`. If it does not exist, note the stack as "no index yet" and skip it.
- Capture any `## Reading Paths` section as retrieval context for that stack.

If all stacks were skipped (none had an index), tell the user to run `/stacks:catalog-sources` in the library.
````

Replace Step 5 body with:

````markdown
## Step 5: Retrieve matching articles across stacks

<!-- STACKS-SEARCH STUB — replace this block when #10 (qmd) lands.
     Contract: input = (QUERY, STACKS_TO_SEARCH[], per-stack article dirs)
     Output = up to 3 (article_path, stack_name) pairs ranked by relevance.
     The answer synthesis in Step 6 depends only on these pairs. -->

Check whether each stack in `STACKS_TO_SEARCH` is in article mode or guide mode:

```bash
for stack in "${STACKS_TO_SEARCH[@]}"; do
  if find "$LIBRARY/$stack/articles" -maxdepth 1 -name '*.md' 2>/dev/null | grep -q .; then
    echo "article $stack"
  else
    echo "guide $stack"
  fi
done
```

**Article mode stacks** (those where `articles/` exists and has `.md` files):

Score articles across ALL article-mode stacks together. For each article, weight matches in this order:
1. `title` frontmatter field — highest weight
2. `tags[]` frontmatter field — high weight
3. Article slug (filename without `.md`) — medium weight
4. Reading Paths context from Step 4 (articles in the same path as a matched article score higher)

Select the top 3 articles globally (across all stacks). Read each article file. Track which stack each article came from.

**Guide mode stacks** (those without `articles/`):

Score guides from all guide-mode stacks together using the same weighting. Select top 3 guides globally. Track which stack each guide came from.

**Mixed case** (some stacks article mode, some guide mode):

Score article-mode and guide-mode results separately, then interleave by relevance score. Cap at 3 total.

If no matches found across any stack in scope: "No matching content found across stacks: {STACKS_TO_SEARCH[*]}."
````

- [ ] **Step 5: Update Step 6 answer format to include stack attribution**

In Step 6 (Synthesize answer), update the response format to include the stack name alongside the article:

````markdown
Format the response as:
```
## Answer

{synthesized answer with specific citations inline}

**Sources**: {article or topic names that contributed}
**Stacks**: {stack name(s) that contributed — e.g., "svelte, sysops"}
```
````

Also update the format note: "If content came from a single stack, use `**Stack**: {name}`. If content came from multiple stacks, use `**Stacks**: {names}`."

- [ ] **Step 6: Verify the stub comment is present**

```bash
grep "STACKS-SEARCH STUB\|REPLACE-WITH-QMD" skills/ask/SKILL.md
```

Expected: 2 matching lines.

- [ ] **Step 7: Version bump and changelog**

Bump minor version (0.18.1 → 0.19.0 — this adds a new feature surface) in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`. Add CHANGELOG entry:

```
## [0.19.0] - 2026-05-10

### Added
- `/stacks:ask`: cross-stack lookup by default (searches all stacks in the library)
- `/stacks:ask --stack {name}`: force single-stack scope (prior behavior)
- `/stacks:ask --stacks {a,b,c}`: scope to a named subset of stacks
- Answer format now cites the contributing stack(s) alongside article names
- Stacks-search stub comment marks the retrieval block for #10 (qmd) replacement

Closes #5.
```

```bash
git add skills/ask/SKILL.md .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md
git commit -m "feat(#5): cross-stack lookup for /stacks:ask with stub for #10 (qmd)"
```

- [ ] **Step 8: Close issues on GitHub**

```bash
gh issue close 50 --comment "Closed by assert-structure.sh + call sites in catalog-sources and audit-stack. Shipped in 0.18.1."
gh issue close 5 --comment "Closed by cross-stack retrieval in skills/ask/SKILL.md. Shipped in 0.19.0."
```

- [ ] **Step 9: Push**

```bash
git push
```

---

## Phase 3 Plan Stub

Phase 3 issues are blocked on design decisions. Each needs a decision before tasks can be written.

### #14: Scheduled loop (process-inbox then catalog-sources on a timer)

**Decision needed — cost guardrail design:**
- Option A: hard cap on sources per scheduled run (e.g., 10 files max), abort if queue is larger
- Option B: dry-run report first, user confirms before actual catalog
- Option C: run unconditionally, but emit token-cost estimate to a log file so the user can audit

The implementation is straightforward once the guardrail shape is chosen. Do not write tasks until this is resolved.

### #40: process-inbox quality gate (high-signal vs low-signal session extracts)

**Decision needed — LLM cost budget per file:**
- The quality gate requires an LLM call per inbox file to score it. Budget needs a ceiling: is 1 LLM call per file acceptable, or do we score in batch?
- What is the pass/fail threshold? (word count floor, source citation floor, concept density floor?)

Do not write tasks until scoring approach and threshold are agreed.

### #10: qmd search integration

**Decision needed — deployment model:**
- Option A: zero-config (embedded Python, no external service) — simpler, limited to FTS
- Option B: local infra (DuckDB or SQLite FTS5, pre-built index) — richer queries, needs index refresh step
- Option C: ship an index-build script + query script, user runs `stacks:build-index` explicitly

The stacks-search stub in Task 4 above marks the exact swap point in `skills/ask/SKILL.md`. Do not write tasks until deployment model is chosen.
