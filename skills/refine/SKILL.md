---
name: refine
description: |
  Use when the user wants to refine a knowledge stack after ingesting sources.
  Cross-references topics, validates guides against sources, synthesizes
  glossary and invariants, and produces findings on coverage and research
  direction. Must be run from within a library repo.
---

# Refine

Cross-reference, validate, synthesize cross-cutting artifacts, and produce findings.

## Step 0: Telemetry

```bash
TELEMETRY_SH=$(find ~/.claude/plugins/cache -name telemetry.sh -path '*/stacks/*/scripts/*' 2>/dev/null | sort -V | tail -1)
if [[ -z "$TELEMETRY_SH" ]]; then
  STACKS_ROOT=$(jq -r '.pluginPaths["stacks@local"] // empty' ~/.claude/settings.json 2>/dev/null)
  TELEMETRY_SH="$STACKS_ROOT/scripts/telemetry.sh"
fi
SKILL_NAME="stacks:refine" bash "$TELEMETRY_SH" 2>/dev/null || true
```

## Step 1: Gate check

```bash
if [[ ! -f "catalog.md" ]]; then
  echo "ERROR: Not in a library repo (no catalog.md)."
  exit 1
fi
STACK="$ARGUMENTS"
if [[ -z "$STACK" ]]; then
  echo "ERROR: Specify a stack name. Usage: /stacks:refine {stack-name}"
  exit 1
fi
if [[ ! -f "$STACK/STACK.md" ]]; then
  echo "ERROR: Stack '$STACK' not found (no STACK.md)."
  exit 1
fi
```

## Step 2: Check prerequisites

Refine requires at least 2 topic guides to cross-reference.

```bash
GUIDE_COUNT=$(find "$STACK/topics" -name "guide.md" 2>/dev/null | wc -l)
if [[ "$GUIDE_COUNT" -lt 2 ]]; then
  echo "Only $GUIDE_COUNT topic guide(s) found. Refine needs 2+ to cross-reference."
  echo "Run /stacks:ingest $STACK to build more topic guides first."
  exit 0
fi
echo "Found $GUIDE_COUNT topic guides. Running 4-wave refine."
```

## Step 3: Wave 3 — Cross-reference

Read `references/wave-engine.md` for the full agent dispatch prompt for the cross-referencer agent.

Find the cross-referencer agent:
```bash
AGENTS_DIR=$(find ~/.claude/plugins/cache -type d -name "agents" -path "*/stacks/*" 2>/dev/null | sort -V | tail -1)
if [[ -z "$AGENTS_DIR" ]]; then
  STACKS_ROOT=$(jq -r '.pluginPaths["stacks@local"] // empty' ~/.claude/settings.json 2>/dev/null)
  AGENTS_DIR="$STACKS_ROOT/agents"
fi
```

Dispatch the cross-referencer agent with:
- All topic guides (`$STACK/topics/*/guide.md`)
- `$STACK/STACK.md`
- Output path: `$STACK/dev/curate/cross-reference-report.md`

Create `$STACK/dev/curate/` directory first:
```bash
mkdir -p "$STACK/dev/curate"
```

Gate: verify `$STACK/dev/curate/cross-reference-report.md` exists before proceeding.

## Step 4: Wave 4 — Validate

Dispatch the validator agent with:
- All topic guides (`$STACK/topics/*/guide.md`)
- All source files (`$STACK/sources/` recursively)
- `$STACK/STACK.md`
- Output path: `$STACK/dev/curate/validation-report.md`

Gate: verify `$STACK/dev/curate/validation-report.md` exists before proceeding.

## Step 5: Wave 5 — Synthesize

Dispatch the synthesizer agent with:
- All topic guides (`$STACK/topics/*/guide.md`)
- `$STACK/STACK.md`
- Output paths: `$STACK/dev/curate/glossary.md` and `$STACK/dev/curate/invariants.md`

Gate: verify both files exist before proceeding.

## Step 6: Wave 6 — Findings

Dispatch the findings-analyst agent with:
- All topic guides (`$STACK/topics/*/guide.md`)
- `$STACK/dev/curate/cross-reference-report.md`
- `$STACK/dev/curate/validation-report.md`
- `$STACK/STACK.md`
- Output path: `$STACK/dev/curate/findings.md`

Gate: verify `$STACK/dev/curate/findings.md` exists before proceeding.

## Step 7: Update log

Prepend entry to `$STACK/log.md`:

```markdown
## [YYYY-MM-DD] refine | cross-reference, validate, synthesize, findings
{contradiction-count} contradictions. {validation-issue-count} validation issues.
Glossary: {term-count} terms. Invariants: {rule-count} rules.
Findings: P1: {p1-count}. P2: {p2-count}. P3: {p3-count}.
Research queue: {top-3-items}.
```

Read the produced reports to extract the counts before writing the log entry.

## Step 8: Commit and report

```bash
git add "$STACK/dev/curate/" "$STACK/log.md"
git commit -m "refine($STACK): cross-reference, validate, synthesize, findings"
```

Present the full refine summary to the user:
- Cross-reference findings (contradictions, cross-link additions, misfilings)
- Validation findings (verified/drift/unsourced/stale counts)
- Cross-cutting artifacts produced (glossary term count, invariant count)
- Coverage and gap findings
- Top research direction items (P1 priorities from findings.md)
