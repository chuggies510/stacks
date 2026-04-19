---
name: audit-stack
description: |
  Use when the user wants to validate articles, synthesize stack-root artifacts,
  and produce structured findings for a knowledge stack. Runs the A1-A5 audit
  pipeline: validator marks article claims inline, synthesizer produces glossary
  and invariants, findings-analyst emits structured items, convergence check
  decides whether to loop, and archive fires on convergence. Must be run from
  within a library repo.
---

# Audit Stack

Validate articles against sources, synthesize cross-cutting artifacts, produce structured findings, check convergence, and archive on completion.

## Step 0: Telemetry

```bash
TELEMETRY_SH=$(find ~/.claude/plugins/cache -name telemetry.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
if [[ -z "$TELEMETRY_SH" ]]; then
  STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
  TELEMETRY_SH="$STACKS_ROOT/scripts/telemetry.sh"
fi
SKILL_NAME="stacks:audit-stack" bash "$TELEMETRY_SH" 2>/dev/null || true
```

## Step 1: Gate check

```bash
if [[ ! -f "catalog.md" ]]; then
  echo "ERROR: Not in a library repo (no catalog.md)."
  exit 1
fi
STACK="$ARGUMENTS"
if [[ -z "$STACK" ]]; then
  echo "ERROR: Specify a stack name. Usage: /stacks:audit-stack {stack-name}"
  exit 1
fi
if [[ ! -f "$STACK/STACK.md" ]]; then
  echo "ERROR: Stack '$STACK' not found (no STACK.md)."
  exit 1
fi
ARTICLE_COUNT=$(find "$STACK/articles" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)
if [[ "$ARTICLE_COUNT" -lt 1 ]]; then
  echo "ERROR: No articles found in $STACK/articles/. Run /stacks:catalog-sources $STACK first."
  exit 1
fi
```

## Step 2: Read STACK.md

Locate plugin helpers. Anchor the lookup on the `scripts/` subdirectory (path-guarded so a similarly-named dir from another plugin cannot collide), then derive every other plugin path from the shared root:

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

WAVE_ENGINE="$STACKS_ROOT/references/wave-engine.md"
AGENTS_DIR="$STACKS_ROOT/agents"
```

Read `$WAVE_ENGINE` for the A1-A5 orchestration contract.

Read `$STACK/STACK.md` to extract:
- Source hierarchy (for validator and synthesizer context)
- `MAX_AUDIT_PASSES` value. Parse with:

```bash
MAX_AUDIT_PASSES=$(grep -oP '(?<=MAX_AUDIT_PASSES:\s)\d+' "$STACK/STACK.md" 2>/dev/null || echo "3")
if [[ -z "$MAX_AUDIT_PASSES" ]] || ! [[ "$MAX_AUDIT_PASSES" =~ ^[0-9]+$ ]]; then
  MAX_AUDIT_PASSES=3
fi
```

## Step 3: Pass loop controller

Initialize convergence tracking:

```bash
prev_empty=0
converged=0
mkdir -p "$STACK/dev/audit/closed"
```

Run the pass loop. Each iteration dispatches A1 through A3, then runs A4 to check convergence. The loop runs until convergence is reached or the pass budget is exhausted.

The `pass_counter` is managed by the findings-analyst agent, which increments it in the `dev/audit/findings.md` frontmatter each pass. After A3 completes, read `pass_counter` from the frontmatter:

```bash
pass_counter=$(grep -oP '(?<=pass_counter:\s)\d+' "$STACK/dev/audit/findings.md" 2>/dev/null || echo "0")
```

The pass loop continues through Steps 4-8 below. At A4 (Step 8), the loop either: sets `converged=1` and breaks, or increments `prev_empty` accordingly and checks whether `pass_counter >= MAX_AUDIT_PASSES`. If the budget cap is reached without convergence, set `converged=1` and break (budget-cap convergence; findings are still archived at A5).

## Step 4: A1 — Validator dispatch

```bash
DISPATCH_EPOCH=$(date +%s)
EXPECTED_ARTICLES=( "$STACK"/articles/*.md )
```

Dispatch the `validator` agent (read `$AGENTS_DIR/validator.md` for the full prompt). Provide:
- All articles: `$STACK/articles/*.md`
- All source files: `$STACK/sources/` recursively, excluding `sources/incoming/` and `sources/trash/`
- `$STACK/STACK.md` (source hierarchy for conflict resolution)

The validator reads each article, strips prior-cycle marks (`[VERIFIED]`, `[DRIFT]`, `[UNSOURCED]`, `[STALE]`), marks each substantive claim inline, and updates the `last_verified` frontmatter field. It edits article files in place.

After the agent returns, gate every article with a per-article loop:

```bash
for article in "${EXPECTED_ARTICLES[@]}"; do
  "$SCRIPTS_DIR/assert-written.sh" "$article" "${DISPATCH_EPOCH}" "validator"
done
```

Do NOT pass the directory path to `assert-written.sh`. Editing files inside a directory does not update the directory's own mtime on Linux; only the individual file mtimes advance.

If any gate fails, halt with the `AGENT_WRITE_FAILURE` error and report which articles were not written.

## Step 5: A2 — Synthesizer dispatch

```bash
DISPATCH_EPOCH=$(date +%s)
```

Dispatch the `synthesizer` agent (read `$AGENTS_DIR/synthesizer.md` for the full prompt). Provide:
- All articles: `$STACK/articles/*.md`
- `$STACK/STACK.md`

The synthesizer reads all articles and writes three files at the stack root:
- `$STACK/glossary.md` — alphabetical term definitions
- `$STACK/invariants.md` — numbered rules with independent corroboration
- `$STACK/contradictions.md` — conflicting claims between articles

After the agent returns, gate each output:

```bash
"$SCRIPTS_DIR/assert-written.sh" "$STACK/glossary.md" "${DISPATCH_EPOCH}" "synthesizer"
"$SCRIPTS_DIR/assert-written.sh" "$STACK/invariants.md" "${DISPATCH_EPOCH}" "synthesizer"
"$SCRIPTS_DIR/assert-written.sh" "$STACK/contradictions.md" "${DISPATCH_EPOCH}" "synthesizer"
```

Halt on any gate failure before proceeding to A2b.

## Step 6: A2b — Wikilink pass

```bash
"$SCRIPTS_DIR/wikilink-pass.sh" "$STACK/articles/" "$STACK/glossary.md"
```

This is the same shared helper used by catalog-sources at W2b. It reads glossary bold terms and rewrites the first occurrence of each term per article as a `[[wikilink]]`. Self-links are excluded. The pass is a no-op if `glossary.md` is absent, but at this point in the pipeline `glossary.md` was just written by A2.

## Step 7: A3 — Findings-analyst dispatch

```bash
DISPATCH_EPOCH=$(date +%s)
mkdir -p "$STACK/dev/audit"
```

Dispatch the `findings-analyst` agent (read `$AGENTS_DIR/findings-analyst.md` for the full prompt). Provide:
- All articles: `$STACK/articles/*.md` (inline marks from A1 are the data source)
- `$STACK/contradictions.md`
- `$STACK/dev/audit/findings.md` (prior pass; may not exist on first run; agent handles gracefully)

The agent writes `dev/audit/findings.md` with this locked frontmatter:
```yaml
---
audit_date: YYYY-MM-DD
stack_head: <git sha>
pass_counter: <int>
schema_version: 3
---
```

The canonical schema definition (item shapes, status enum, resolvable_by enum, emit-time rules, and carry-forward behavior) lives in `agents/findings-analyst.md` — do not duplicate it here.

After the agent returns, gate the output:

```bash
"$SCRIPTS_DIR/assert-written.sh" "$STACK/dev/audit/findings.md" "${DISPATCH_EPOCH}" "findings-analyst"
```

Read `pass_counter` from the written file for the loop controller:

```bash
pass_counter=$(grep -oP '(?<=pass_counter:\s)\d+' "$STACK/dev/audit/findings.md" 2>/dev/null || echo "0")
```

## Step 8: A4 — Convergence check

Count open work in the current findings file. Terminal statuses are `applied`, `closed`, `deferred`, `stale`, `failed`.

```bash
FINDINGS="$STACK/dev/audit/findings.md"

# Count items with status: open
open_count=$(grep -c '^\s*status:\s*open\s*$' "$FINDINGS" 2>/dev/null || echo "0")

# Count items resolvable within audit-stack's own scope (resynthesize, noop) that are still open. Items with resolvable_by: catalog-sources (fetch_source) or resolvable_by: external (research_question) are out of audit-stack's domain and do not block convergence.
generative_open=$(awk '
  /^- id:/ {
    if (in_item && resolvable_by == "audit-stack" && status != "terminal") count++
    in_item=1; resolvable_by=""; status=""
    next
  }
  in_item && /resolvable_by: audit-stack/ { resolvable_by="audit-stack" }
  in_item && /status: (applied|closed|deferred|stale|failed)/ { status="terminal" }
  END {
    if (in_item && resolvable_by == "audit-stack" && status != "terminal") count++
    print count+0
  }
' "$FINDINGS" 2>/dev/null || echo "0")

# Determine empty-pass: both counters must be zero
if [[ "$open_count" -eq 0 && "$generative_open" -eq 0 ]]; then
  empty_pass=1
else
  empty_pass=0
fi
```

Apply convergence logic:

```bash
if [[ "$empty_pass" -eq 1 ]]; then
  if [[ "$prev_empty" -eq 1 ]]; then
    # 2 consecutive empty passes: convergence
    converged=1
  else
    prev_empty=1
    echo "Pass $pass_counter complete: empty pass (open=$open_count, generative_open=$generative_open). Running one more pass to confirm convergence."
  fi
else
  prev_empty=0
  echo "Pass $pass_counter complete: open=$open_count, generative_open=$generative_open (fetch_source + research_question)."
  if [[ "$pass_counter" -ge "$MAX_AUDIT_PASSES" ]]; then
    echo "Budget cap reached ($MAX_AUDIT_PASSES passes). Treating as converged."
    converged=1
  else
    echo "Continuing to next pass (pass $((pass_counter + 1)) of $MAX_AUDIT_PASSES)."
  fi
fi
```

If `converged=0` and the budget has not been reached, loop back to Step 4 (next pass begins at A1). If `converged=1`, proceed to Step 9.

## Step 9: A5 — Archive on convergence

This step runs only when `converged=1`.

Read `audit_date` from the frontmatter of the converged findings file before moving it:

```bash
audit_date=$(grep -oP '(?<=audit_date:\s)\S+' "$STACK/dev/audit/findings.md" 2>/dev/null | head -1)
if [[ -z "$audit_date" ]]; then
  audit_date=$(date +%Y-%m-%d)
fi

mkdir -p "$STACK/dev/audit/closed"
cp "$STACK/dev/audit/findings.md" "$STACK/dev/audit/closed/${audit_date}-findings.md"
```

The archived file at `dev/audit/closed/{audit_date}-findings.md` is the historical record. The active `dev/audit/findings.md` remains in place and carries forward into the next catalog-sources W0b pass (feedback flywheel: terminal-status items become the skip list; open items remain open work for the next cycle).

## Step 10: Log and commit

Prepend an entry to `$STACK/log.md`:

```markdown
## [YYYY-MM-DD] audit-stack | pass_counter={N}, converged={true/false}
open_items_at_close={count}. Archived: dev/audit/closed/{audit_date}-findings.md
Glossary: {term-count} terms. Invariants: {rule-count} rules. Contradictions: {contradiction-count}.
```

Before writing, extract counts from the synthesized files:
- Glossary: count `**Term**:` lines in `$STACK/glossary.md`
- Invariants: count numbered rule lines (lines matching `^\d+\.`) in `$STACK/invariants.md`
- Contradictions: count `## ` section headers in `$STACK/contradictions.md`

Then commit:

```bash
git add "$STACK/glossary.md" "$STACK/invariants.md" "$STACK/contradictions.md" \
        "$STACK/articles/" "$STACK/dev/audit/" "$STACK/log.md"
git commit -m "audit($STACK): pass ${pass_counter}, converged=${converged}"
```

Present a summary to the user:
- Pass count completed and convergence outcome
- Validator findings: VERIFIED/DRIFT/UNSOURCED/STALE mark counts across all articles
- Synthesized artifacts: glossary term count, invariant count, contradiction count
- Findings: open item count at close, fetch_source vs resynthesize vs research_question breakdown
- Archive path (if converged) or next recommended action (if budget-capped without convergence)
