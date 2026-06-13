---
name: audit-stack
description: |
  Use when the user wants to check a knowledge stack's articles against their
  cited sources. Dispatches the validator agent to mark each claim inline
  (VERIFIED/DRIFT/UNSOURCED/STALE), then writes a fresh drift report listing
  every flagged claim. Stateless: each run regenerates the report from scratch,
  no carry-forward ledger. Must be run from within a library repo.
---

# Audit Stack

Validate a stack's articles against their cited sources, then report what drifted, what is unsourced, and what is stale. Each run is independent: the validator re-marks every article and the report is rebuilt from the current marks. There is no carry-forward ledger and no multi-pass loop.

## Step 0: Telemetry

```bash
LOCATE=$(find ~/.claude/plugins/cache -name locate-plugin-root.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
[[ -z "$LOCATE" ]] && LOCATE="$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)/scripts/locate-plugin-root.sh"
STACKS_ROOT=$(bash "$LOCATE" 2>/dev/null)
SKILL_NAME="stacks:audit-stack" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
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
SCRIPTS_DIR="$STACKS_ROOT/scripts"
```

## Step 2: Read STACK.md

Read `$STACK/STACK.md` for the source-hierarchy section. The validator needs it to resolve conflicts when two sources disagree (higher-tier source wins → lower-tier claim marked `[STALE]`).

## Step 3: A1 — Validate articles against sources

Dispatch the `stacks:validator` agent over the articles. One agent unless the article count exceeds the cap (the cap bounds how many articles a single agent re-reads in one pass, and — when sliced — how many subagents spawn at once). Slice inline with the same `${ARRAY[@]:i:CAP}` idiom catalog W2 uses.

```bash
mapfile -t ARTICLES < <(find "$STACK/articles" -maxdepth 1 -name '*.md' | sort)
N_ARTICLES=${#ARTICLES[@]}
CAP=25
DISPATCH_EPOCH=$(date +%s)
mkdir -p "$STACK/dev/audit"
```

**Dispatch.** Each validator gets: the absolute article paths in its slice, the stack's sources directory `$STACK/sources/` (the agent reads what each claim cites; it excludes `sources/incoming/` and `sources/trash/`), the source-hierarchy context from STACK.md, the stack root, and `$DISPATCH_EPOCH`. The validator strips prior-cycle marks, writes fresh inline `[VERIFIED]/[DRIFT]/[UNSOURCED]/[STALE]` marks, and sets `last_verified` to today.

- **N_ARTICLES ≤ CAP:** one `Agent` call (subagent_type `stacks:validator`) over all of `${ARTICLES[@]}`.
- **N_ARTICLES > CAP:** in a single message, emit one `Agent` call per slice `${ARTICLES[@]:i:CAP}` (i = 0, CAP, 2·CAP, …). Parallel dispatch — never sequential.

**Gate.** After all validators return, the parent re-runs the write-or-fail + marker-shape gate inline over every article:

```bash
bash "$SCRIPTS_DIR/gate-batch.sh" "$DISPATCH_EPOCH" "validator-gate" article-validated "${ARTICLES[@]}"
```

A non-zero exit means an article was not freshly written or carries no validation marker — surface the failing paths and stop.

## Step 4: Drift report

Rebuild `dev/audit/report.md` from the current marks. The report is regenerated every run; it is not a ledger.

```bash
REPORT="$STACK/dev/audit/report.md"
TODAY=$(date +%Y-%m-%d)
count() { grep -rohE "\\[$1\\]" "$STACK/articles" 2>/dev/null | wc -l | tr -d ' '; }
{
  echo "# $STACK — audit drift report ($TODAY)"
  echo
  echo "Regenerated fresh each audit. Not a persistent ledger."
  echo
  echo "VERIFIED: $(count VERIFIED)  DRIFT: $(count DRIFT)  UNSOURCED: $(count UNSOURCED)  STALE: $(count STALE)"
  echo
  echo "## Flagged claims"
  echo
  flagged=0
  for art in "$STACK"/articles/*.md; do
    [[ -e "$art" ]] || continue
    slug=$(basename "$art" .md)
    while IFS= read -r line; do
      flagged=1
      mark=$(echo "$line" | grep -oE '\[(DRIFT|UNSOURCED|STALE)\]' | head -1)
      claim=$(echo "$line" | sed -E 's/^[0-9]+://; s/^[[:space:]]+//')
      echo "- \`$slug\` $mark — $claim"
    done < <(grep -nE '\[(DRIFT|UNSOURCED|STALE)\]' "$art")
  done
  [[ "$flagged" -eq 0 ]] && echo "_None. Every cited claim verified against its source._"
} > "$REPORT"
echo "Wrote $REPORT"
```

## Step 5: Log and commit

Prepend an entry to `$STACK/log.md`:

```markdown
## [YYYY-MM-DD] audit-stack
VERIFIED={v} DRIFT={d} UNSOURCED={u} STALE={s}. Report: dev/audit/report.md
```

Then commit the re-marked articles and the report:

```bash
git add "$STACK/articles/" "$STACK/dev/audit/report.md" "$STACK/log.md"
git commit -m "audit($STACK): drift report — D={d} U={u} S={s}"
```

Present a summary to the user: the four mark counts, the count of flagged claims, and the report path. If DRIFT or STALE counts are non-zero, name the most affected articles so the operator knows where to re-catalog or fix sources.
