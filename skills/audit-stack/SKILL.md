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

## Step 4: A1 — Parent-side parallel validator dispatch

The parent skill (this session) shards articles directly and dispatches `validator` agents in parallel. The `validator-orchestrator` agent is **deprecated for this skill** — nested Task dispatch was unreliable and the orchestrator silently fell back to inline execution, defeating the sharding. Parent-side dispatch keeps Task usage shallow (always reachable) and lets the parent do the deterministic merge.

**Batch size: ≤3 articles per validator agent.** Per-agent isolation matters more than minimizing dispatch count. Each validator reads its 1-3 articles plus the full `$STACK/sources/` tree and writes inline VERIFIED/DRIFT/UNSOURCED/STALE marks. Bundling many unrelated articles into one agent invites cross-article confusion and source misattribution. The previous 15-per-shard cap was a workaround for a problem this design doesn't have.

```bash
ARTICLES=$(find "$STACK/articles" -maxdepth 1 -name '*.md' | sort)
N_ARTICLES=$(echo "$ARTICLES" | grep -c .)
BATCH_SIZE=3
N_BATCHES=$(( (N_ARTICLES + BATCH_SIZE - 1) / BATCH_SIZE ))
DISPATCH_EPOCH=$(date +%s)
mkdir -p "$STACK/dev/audit"

# Build batch files: dev/audit/_a1-batch-{NN}.txt with one article path per line.
echo "$ARTICLES" | awk -v bs="$BATCH_SIZE" -v stack="$STACK" '
  { batch = int((NR-1)/bs); printf "%s\n", $0 > sprintf("%s/dev/audit/_a1-batch-%02d.txt", stack, batch) }
'
```

**Dispatch:** in a single message, emit one `Agent` tool call per batch (subagent_type `stacks:validator`). Each prompt names the absolute paths in that batch's `_a1-batch-NN.txt`, the stack root, the sources tree path, and the `$DISPATCH_EPOCH`. Tell each validator to use `assert-written.sh "$ARTICLE_PATH" "$DISPATCH_EPOCH" "validator"` for each article it edits, and to fail loudly if a gate trips. Parallel dispatch is mandatory — sequential dispatch reintroduces the wall-clock problem the orchestrator was meant to solve.

**Gate:** after all validator agents return, the parent re-runs the gate inline:

```bash
FAILED=()
for batch in "$STACK"/dev/audit/_a1-batch-*.txt; do
  while IFS= read -r article; do
    [[ -z "$article" ]] && continue
    if ! "$SCRIPTS_DIR/assert-written.sh" "$article" "$DISPATCH_EPOCH" "validator-parent-gate" 2>/dev/null; then
      FAILED+=("$article")
    fi
  done < "$batch"
done
if [[ ${#FAILED[@]} -gt 0 ]]; then
  printf 'AGENT_WRITE_FAILURE: A1 articles ungated:\n'
  printf '  %s\n' "${FAILED[@]}"
  exit 1
fi
```

**Summary write:** the parent writes `_a1-summary.json` itself:

```bash
jq -n \
  --argjson n_articles "$N_ARTICLES" \
  --argjson n_batches "$N_BATCHES" \
  --argjson batch_size "$BATCH_SIZE" \
  --argjson epoch "$DISPATCH_EPOCH" \
  '{schema_version:1, wave:"a1", status:"ok",
    counts:{n_articles:$n_articles, n_batches:$n_batches, articles_per_agent:$batch_size},
    epochs:{dispatch_epoch:$epoch}}' \
  > "$STACK/dev/audit/_a1-summary.json"
```

Cleanup batch files (`rm "$STACK"/dev/audit/_a1-batch-*.txt`) after summary writes.

## Step 5: A2 — Parent-side parallel synthesizer dispatch + merge

Synthesizer needs cross-article view to dedup glossary terms, find independent-corroboration invariants, and surface contradictions. So A2 keeps the shard-then-merge pattern, but driven from the parent (not via `synthesizer-orchestrator`, which is **deprecated for this skill**).

**Batch size: ≤10 articles per synthesizer shard.** Smaller than the prior 30-cap because per-agent attention to each article matters: a shard producing 25 candidate glossary entries from 30 articles silently misses terms that a shard of 8 articles would catch. Synthesizer reads article bodies only (no sources tree), so per-agent context stays small.

**Phase A — shard fan-out:**

```bash
ARTICLES=$(find "$STACK/articles" -maxdepth 1 -name '*.md' | sort)
N_ARTICLES=$(echo "$ARTICLES" | grep -c .)
BATCH_SIZE_A2=10
N_BATCHES_A2=$(( (N_ARTICLES + BATCH_SIZE_A2 - 1) / BATCH_SIZE_A2 ))
DISPATCH_EPOCH=$(date +%s)
echo "$ARTICLES" | awk -v bs="$BATCH_SIZE_A2" -v stack="$STACK" '
  { batch = int((NR-1)/bs); printf "%s\n", $0 > sprintf("%s/dev/audit/_a2-batch-%02d.txt", stack, batch) }
'
```

In a single message, dispatch one `stacks:synthesizer` agent per batch. Each prompt: stack root, batch file path, output path `dev/audit/_a2-partial-{NN}.md` (a single markdown file with `## Glossary`, `## Invariants`, `## Contradictions` sections covering only that shard's articles), and `$DISPATCH_EPOCH`. The agent must call `assert-written.sh "$PARTIAL_PATH" "$DISPATCH_EPOCH" "synthesizer"` after writing.

**Gate Phase A:**

```bash
for i in $(seq -f "%02g" 0 $((N_BATCHES_A2 - 1))); do
  PARTIAL="$STACK/dev/audit/_a2-partial-$i.md"
  if ! "$SCRIPTS_DIR/assert-written.sh" "$PARTIAL" "$DISPATCH_EPOCH" "synthesizer-parent-gate" 2>/dev/null; then
    echo "AGENT_WRITE_FAILURE: A2 partial $PARTIAL ungated"; exit 1
  fi
done
```

**Phase B — merge pass:** dispatch ONE `stacks:synthesizer` agent (single Task call, not parallel). Prompt it to read all `dev/audit/_a2-partial-*.md` files, apply dedup + independent-corroboration + tier-hierarchy resolution across shards, and write the three final stack-root files: `$STACK/glossary.md`, `$STACK/invariants.md`, `$STACK/contradictions.md`. Each must be gated with `assert-written.sh ... "$DISPATCH_EPOCH" "synthesizer-merge"`.

If `N_BATCHES_A2 == 1`, skip Phase B and have the single Phase A agent write the three stack-root files directly instead of a partial.

**Gate Phase B + summary write:**

```bash
for f in glossary.md invariants.md contradictions.md; do
  if ! "$SCRIPTS_DIR/assert-written.sh" "$STACK/$f" "$DISPATCH_EPOCH" "synthesizer-merge-gate" 2>/dev/null; then
    echo "AGENT_WRITE_FAILURE: A2 stack-root $f ungated"; exit 1
  fi
done
G_TERMS=$(grep -c '^\*\*' "$STACK/glossary.md" 2>/dev/null || echo 0)
INV_COUNT=$(grep -c '^[0-9]\+\.' "$STACK/invariants.md" 2>/dev/null || echo 0)
CON_COUNT=$(grep -c '^## ' "$STACK/contradictions.md" 2>/dev/null || echo 0)
jq -n \
  --argjson n_articles "$N_ARTICLES" \
  --argjson n_batches "$N_BATCHES_A2" \
  --argjson g "$G_TERMS" --argjson i "$INV_COUNT" --argjson c "$CON_COUNT" \
  --argjson epoch "$DISPATCH_EPOCH" \
  '{schema_version:1, wave:"a2", status:"ok",
    counts:{n_articles:$n_articles, n_batches:$n_batches,
            glossary_terms:$g, invariants:$i, contradictions:$c},
    epochs:{dispatch_epoch:$epoch}}' \
  > "$STACK/dev/audit/_a2-summary.json"
rm "$STACK"/dev/audit/_a2-batch-*.txt
```

After A2 succeeds the three stack-root files are present and gated; proceed to A2b.

## Step 6: A2b — Wikilink pass

```bash
"$SCRIPTS_DIR/wikilink-pass.sh" "$STACK/articles/" "$STACK/glossary.md"
```

This is the same shared helper used by catalog-sources at W2b. It reads glossary bold terms and rewrites the first occurrence of each term per article as a `[[wikilink]]`. Self-links are excluded. The pass is a no-op if `glossary.md` is absent, but at this point in the pipeline `glossary.md` was just written by A2.

## Step 7: A3 — Parent-side parallel findings-analyst dispatch + deterministic merge

The `findings-analyst-orchestrator` agent is **deprecated for this skill** — same root cause as A1 and A2. Parent shards directly, dispatches in parallel, and merges with awk in the parent process (the merge is deterministic terminal-wins-by-id; no agent needed).

**Batch size: ≤3 articles per findings-analyst agent**, matching A1. Each agent reads its 1-3 articles' inline marks, the stack-level `contradictions.md`, the prior `dev/audit/findings.md` (for carry-forward of terminal-status items by id), and writes a partial findings file covering only the items it identifies.

```bash
ARTICLES=$(find "$STACK/articles" -maxdepth 1 -name '*.md' | sort)
N_ARTICLES=$(echo "$ARTICLES" | grep -c .)
BATCH_SIZE_A3=3
N_BATCHES_A3=$(( (N_ARTICLES + BATCH_SIZE_A3 - 1) / BATCH_SIZE_A3 ))
DISPATCH_EPOCH=$(date +%s)
echo "$ARTICLES" | awk -v bs="$BATCH_SIZE_A3" -v stack="$STACK" '
  { batch = int((NR-1)/bs); printf "%s\n", $0 > sprintf("%s/dev/audit/_a3-batch-%02d.txt", stack, batch) }
'
```

**Dispatch:** in a single message, one `stacks:findings-analyst` agent per batch. Each prompt: stack root, batch file, output partial path `dev/audit/_a3-partial-{NN}.md`, prior `dev/audit/findings.md` path (read-only for carry-forward), `dev/audit/contradictions.md`, and `$DISPATCH_EPOCH`. The agent writes its partial and gates via `assert-written.sh`.

The canonical findings.md schema (item shape, status enum, resolvable_by enum, carry-forward rules) lives in `agents/findings-analyst.md`. The merged file's frontmatter remains:

```yaml
---
audit_date: YYYY-MM-DD
stack_head: <git sha>
pass_counter: <int>
schema_version: 4
---
```

**Gate partials:**

```bash
for i in $(seq -f "%02g" 0 $((N_BATCHES_A3 - 1))); do
  PARTIAL="$STACK/dev/audit/_a3-partial-$i.md"
  if ! "$SCRIPTS_DIR/assert-written.sh" "$PARTIAL" "$DISPATCH_EPOCH" "findings-analyst-parent-gate" 2>/dev/null; then
    echo "AGENT_WRITE_FAILURE: A3 partial $PARTIAL ungated"; exit 1
  fi
done
```

**Deterministic merge in parent (no agent needed):** terminal-wins precedence by item id. A terminal status (`applied`, `closed`, `deferred`, `stale`, `failed`) in any partial overrides an `open` status for the same id. Within terminals, latest wins (last partial scanned). Items appearing only once carry through.

```bash
PRIOR_FINDINGS="$STACK/dev/audit/findings.md"
PRIOR_PASS_COUNTER=$(grep -oP '(?<=pass_counter:\s)\d+' "$PRIOR_FINDINGS" 2>/dev/null || echo 0)
NEW_PASS_COUNTER=$((PRIOR_PASS_COUNTER + 1))
STACK_HEAD=$(git rev-parse HEAD 2>/dev/null || echo unknown)
AUDIT_DATE=$(date +%Y-%m-%d)
TMP_MERGED=$(mktemp)
{
  printf -- '---\naudit_date: %s\nstack_head: %s\npass_counter: %d\nschema_version: 4\n---\n\n' \
    "$AUDIT_DATE" "$STACK_HEAD" "$NEW_PASS_COUNTER"
  cat "$STACK"/dev/audit/_a3-partial-*.md
} > "$TMP_MERGED"

# Awk merge: keep last occurrence of each id, with terminal precedence enforced.
# Reads block-by-block where a block starts at `- id:` and ends at the next blank line.
awk '
  BEGIN { RS=""; FS="\n" }
  /^- id:/ {
    id=""; status="open"
    for (i=1; i<=NF; i++) {
      if (match($i, /^[[:space:]]*id:[[:space:]]*(.*)/, m1)) id=m1[1]
      if (match($i, /^[[:space:]]*status:[[:space:]]*(.*)/, m2)) status=m2[1]
    }
    if (id == "") next
    is_terminal = (status ~ /^(applied|closed|deferred|stale|failed)$/)
    if (!(id in seen) || (is_terminal && !seen_terminal[id])) {
      block[id] = $0
      seen[id] = 1
      if (is_terminal) seen_terminal[id] = 1
    }
  }
  END { for (id in block) print block[id]; print "" }
' "$TMP_MERGED" > "$PRIOR_FINDINGS.merged"

# Prepend frontmatter
{
  printf -- '---\naudit_date: %s\nstack_head: %s\npass_counter: %d\nschema_version: 4\n---\n\n' \
    "$AUDIT_DATE" "$STACK_HEAD" "$NEW_PASS_COUNTER"
  cat "$PRIOR_FINDINGS.merged"
} > "$PRIOR_FINDINGS"
rm -f "$PRIOR_FINDINGS.merged" "$TMP_MERGED"

# Gate and counts
"$SCRIPTS_DIR/assert-written.sh" "$PRIOR_FINDINGS" "$DISPATCH_EPOCH" "findings-merge" || { echo "AGENT_WRITE_FAILURE: merged findings ungated"; exit 1; }
NEW_ITEMS=$(grep -c '^- id:' "$PRIOR_FINDINGS")
CARRIED=0  # operator-readable diff against prior file is out of scope here
ROTATED=0

jq -n \
  --argjson n_articles "$N_ARTICLES" \
  --argjson n_batches "$N_BATCHES_A3" \
  --argjson new_items "$NEW_ITEMS" \
  --argjson carried "$CARRIED" \
  --argjson rotated "$ROTATED" \
  --argjson epoch "$DISPATCH_EPOCH" \
  '{schema_version:1, wave:"a3", status:"ok",
    counts:{n_articles:$n_articles, n_batches:$n_batches,
            new_items:$new_items, carried_items:$carried, rotated_items:$rotated},
    epochs:{dispatch_epoch:$epoch}}' \
  > "$STACK/dev/audit/_a3-summary.json"
rm "$STACK"/dev/audit/_a3-batch-*.txt "$STACK"/dev/audit/_a3-partial-*.md
```

The deterministic-merge approach removes a class of failures the prior orchestrator pattern introduced: cross-shard id collisions resolved by an agent's judgment instead of by code. Carry-forward of terminal-status items from the prior `findings.md` is the responsibility of each `findings-analyst` agent (it reads the prior file); the parent merge is purely about combining the partials.

After A3 succeeds, read `pass_counter` from the written `findings.md` for the loop controller (A4 reads it too):

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

If `converged=0` and the budget has not been reached, loop back to Step 4 (next pass begins at A1). If `converged=1`, proceed to Step 8.5.

## Step 8.5: Rotate stale terminal findings

This step runs only when `converged=1` (per the A4 decision above). It runs before A5 archive so the archive snapshot reflects the post-rotation active file.

Items in a terminal status (`applied`, `closed`, `deferred`, `stale`, `failed`) for ≥ `ROTATION_CYCLES` distinct audit cycles (default 3, parsed from `STACK.md`) are moved from the active `dev/audit/findings.md` to `dev/audit/findings-archive.md`. The archive is append-only, chronological, and operator-readable. Findings-analyst carry-forward reads the active file only; rotated items drop out of the working set.

```bash
audit_date=$(grep -oP '(?<=audit_date:\s)\S+' "$STACK/dev/audit/findings.md" 2>/dev/null | head -1)
if [[ -z "$audit_date" ]]; then
  audit_date=$(date +%Y-%m-%d)
fi
DISPATCH_EPOCH=$(date +%s)
ROTATION_OUTPUT=$(bash "$SCRIPTS_DIR/rotate-findings.sh" "$STACK" "$audit_date")
echo "$ROTATION_OUTPUT"
rotated_count=$(echo "$ROTATION_OUTPUT" | grep -oP '(?<=rotated_items=)\d+' || echo "0")
if [[ "$rotated_count" -gt 0 ]]; then
  "$SCRIPTS_DIR/assert-written.sh" "$STACK/dev/audit/findings-archive.md" "${DISPATCH_EPOCH}" "rotate-findings"
fi
```

The assert-written gate fires only when the script reports a non-zero rotation, so zero-rotation runs (common during the stack's first terminal accumulation years) are no-ops.

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
