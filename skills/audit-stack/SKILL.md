---
name: audit-stack
description: |
  Use when the user wants to check a knowledge stack's articles against their
  cited sources. Dispatches the validator agent to fix source-contradictions in
  place and list soft spots (claims not tied to a source), then writes a fresh
  audit report. Stateless: each run regenerates the report from scratch, no
  carry-forward ledger. Must be run from within a library repo.
---

# Audit Stack

Validate a stack's articles against their cited sources. The validator **fixes** claims that contradict their source in place (so `/ask` never serves a known-wrong claim) and records every fix plus every **soft spot** (a claim not tied to any cited source) for the report. No inline marks are stamped in article bodies. Each run is independent: the validator re-checks every article and the report is rebuilt from this run's findings. There is no carry-forward ledger and no multi-pass loop.

## Step 0: Telemetry

```bash
STACKS_ROOT="$CLAUDE_PLUGIN_ROOT"
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
rm -f "$STACK"/dev/audit/_audit-*.md   # clear any stale per-batch files from a prior run
```

**Dispatch.** Each validator gets: the absolute article paths in its slice, the stack's sources directory `$STACK/sources/` (the agent reads what each claim cites; it excludes `sources/incoming/` and `sources/trash/`), the source-hierarchy context from STACK.md, the stack root `$STACK`, `$DISPATCH_EPOCH`, and a **`BATCH_TAG`** = the slice index (`0`, `1`, `2`, …; use `0` for the single-agent case). The validator strips prior-cycle marks, fixes source-contradictions in place, sets `last_verified` to today, and writes its findings to `$STACK/dev/audit/_audit-${BATCH_TAG}.md` (tab-separated `CORRECTION`/`SOFTSPOT` lines, or empty if clean).

- **N_ARTICLES ≤ CAP:** one `Agent` call (subagent_type `stacks:validator`) over all of `${ARTICLES[@]}`, `BATCH_TAG=0`.
- **N_ARTICLES > CAP:** in a single message, emit one `Agent` call per slice `${ARTICLES[@]:i:CAP}` (i = 0, CAP, 2·CAP, …), with `BATCH_TAG` = the slice ordinal (0, 1, 2, …). Parallel dispatch — never sequential.

**Gate.** After all validators return, the parent re-runs the write-or-fail + shape gate inline over every article. The validated shape is now a populated `last_verified:` date (no inline marks):

```bash
bash "$SCRIPTS_DIR/gate-batch.sh" "$DISPATCH_EPOCH" "validator-gate" article-validated "${ARTICLES[@]}"
```

A non-zero exit means an article was not freshly written or its `last_verified` was not set to a date — surface the failing paths and stop.

## Step 4: Audit report

Rebuild `dev/audit/report.md` from this run's validator findings (the `_audit-*.md` batch files). The report is regenerated every run; it is not a ledger. Two sections: **corrections applied** (claims the validator fixed in place against their source) and **soft spots** (claims not tied to any cited source — left in place for the operator to source or confirm).

```bash
REPORT="$STACK/dev/audit/report.md"
TODAY=$(date +%Y-%m-%d)
# Aggregate the tab-separated CORRECTION/SOFTSPOT lines across all batch files.
AUDIT_LINES=$(cat "$STACK"/dev/audit/_audit-*.md 2>/dev/null || true)
N_CORR=$(printf '%s\n' "$AUDIT_LINES" | grep -c '^CORRECTION'$'\t' || true)
N_SOFT=$(printf '%s\n' "$AUDIT_LINES" | grep -c '^SOFTSPOT'$'\t' || true)
emit() { # $1 = KIND, prints "- `slug` — description" per matching line
  printf '%s\n' "$AUDIT_LINES" | awk -F'\t' -v k="$1" '$1==k{printf "- `%s` — %s\n", $2, $3}'
}
{
  echo "# $STACK — audit report ($TODAY)"
  echo
  echo "Regenerated fresh each audit. Not a persistent ledger."
  echo
  echo "Articles validated: $N_ARTICLES.  Corrections applied: $N_CORR.  Soft spots: $N_SOFT."
  echo
  echo "## Corrections applied"
  echo "_Claims the validator rewrote in place to match their cited source._"
  echo
  if [[ "$N_CORR" -gt 0 ]]; then emit CORRECTION; else echo "_None. No cited claim contradicted its source._"; fi
  echo
  echo "## Soft spots"
  echo "_Claims not tied to a cited source. Left in place — add a source or confirm._"
  echo
  if [[ "$N_SOFT" -gt 0 ]]; then emit SOFTSPOT; else echo "_None. Every claim ties to a cited source._"; fi
} > "$REPORT"
rm -f "$STACK"/dev/audit/_audit-*.md   # transient inputs; the report is the durable artifact
echo "Wrote $REPORT"
```

## Step 5: Log and commit

Prepend an entry to `$STACK/log.md`:

```markdown
## [YYYY-MM-DD] audit-stack
Validated={N_ARTICLES} Corrections={N_CORR} SoftSpots={N_SOFT}. Report: dev/audit/report.md
```

Then commit the corrected articles and the report:

```bash
git add "$STACK/articles/" "$STACK/dev/audit/report.md" "$STACK/log.md"
git commit -m "audit($STACK): corrections=$N_CORR soft-spots=$N_SOFT"
```

Present a summary to the user: articles validated, corrections applied, soft-spot count, and the report path. If corrections were applied, name the most-corrected articles so the operator can eyeball the auto-edits (they are also visible in the commit diff). If soft spots are high, point at the report.
