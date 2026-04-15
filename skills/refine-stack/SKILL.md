---
name: refine-stack
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
  STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
  TELEMETRY_SH="$STACKS_ROOT/scripts/telemetry.sh"
fi
SKILL_NAME="stacks:refine-stack" bash "$TELEMETRY_SH" 2>/dev/null || true
```

## Step 1: Gate check

```bash
if [[ ! -f "catalog.md" ]]; then
  echo "ERROR: Not in a library repo (no catalog.md)."
  exit 1
fi
STACK="$ARGUMENTS"
if [[ -z "$STACK" ]]; then
  echo "ERROR: Specify a stack name. Usage: /stacks:refine-stack {stack-name}"
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
  echo "Run /stacks:ingest-sources $STACK to build more topic guides first."
  exit 0
fi
echo "Found $GUIDE_COUNT topic guides. Running 4-wave refine."
```

## Step 3: Wave 3 — Cross-reference

```bash
# Locate wave-engine.md in the stacks plugin
WAVE_ENGINE=$(find ~/.claude/plugins/cache -name "wave-engine.md" -path "*/stacks/*/references/*" 2>/dev/null | sort -V | tail -1)
if [[ -z "$WAVE_ENGINE" ]]; then
  STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
  WAVE_ENGINE="$STACKS_ROOT/references/wave-engine.md"
fi
```

Read `$WAVE_ENGINE` for the full agent dispatch prompt for the cross-referencer agent.

Find the cross-referencer agent:
```bash
AGENTS_DIR=$(find ~/.claude/plugins/cache -type d -name "agents" -path "*/stacks/*" 2>/dev/null | sort -V | tail -1)
if [[ -z "$AGENTS_DIR" ]]; then
  STACKS_ROOT=$(jq -r '.stacks.installLocation // empty' ~/.claude/plugins/known_marketplaces.json 2>/dev/null)
  AGENTS_DIR="$STACKS_ROOT/agents"
fi
```

Create the output directory, then dispatch the cross-referencer agent:

```bash
mkdir -p "$STACK/dev/curate"
```

Dispatch the cross-referencer agent with:
- All topic guides (`$STACK/topics/*/guide.md`)
- `$STACK/STACK.md`
- Output path: `$STACK/dev/curate/cross-reference-report.md`

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

Before writing the log entry, read the produced reports and extract:
- **Cross-reference report**: count the contradiction entries (lines starting with `- **CONTRADICTION**` or the findings table rows marked as contradictions)
- **Validation report**: count total findings by status (DRIFT + STALE = issues, UNSOURCED = separate)
- **Glossary**: count `**Term**:` lines
- **Invariants**: count numbered rule entries
- **Findings**: count P1, P2, P3 entries; extract the top 3 research direction items from the Research Direction section

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

End the report with: "Proceed with gap-filling?" If the user confirms, run Step 9.

## Step 9: Gap-filling (Karpathy loop)

This step closes the research queue automatically. Karpathy's core principle: identifying gaps is only half the job — the LLM should also fill them. The human curates direction; the LLM does the work.

Read `$STACK/dev/curate/findings.md`. For each P1 and P2 research item:

1. **Identify the source.** Each research item names a specific documentation page, GitHub README, or official reference. Extract the URL or location.

2. **Fetch and save.** For web sources: use WebFetch to retrieve the content and save it as a clean markdown file in `$STACK/sources/incoming/`. Prepend frontmatter:
   ```
   # {Title}
   Source: {URL}
   Tier: {Official | Core team | Practitioner | General}
   ```
   Name the file descriptively: `{publisher}-{topic-slug}.md`. Skip sources that are already in the stack (check `$STACK/index.md`).

3. **Report what was fetched** before proceeding — file names, tiers, and which P1/P2 item each closes.

4. **Re-run ingest waves on new sources only.** After fetching, run Wave 0b (cluster into existing plan), then Wave 1 (extract) and Wave 2 (synthesize) for only the affected topic groups. Do not re-run waves for unaffected topics. File sources from incoming/ to their publisher directories.

5. **Update index.md and log.md**, then commit:
   ```bash
   git add "$STACK/"
   git commit -m "feat($STACK): gap-fill {N} P1/P2 sources from findings"
   ```

**Judgment rules for gap-filling:**

- Only fetch sources the findings explicitly name or point to (official docs, specific GitHub READMEs, named blog posts). Do not speculatively fetch tangentially related content.
- If a P1/P2 item says "add X as a Tier 1 source" and X is a well-known official doc page, fetch it. If the item is vague ("find practitioner experience"), skip it — that requires human curation.
- P3 items (new topic guides, missing topics) are not gap-filled here. They require human direction to scope. Flag them in the report and stop.
- If a fetch fails (404, paywalled, requires auth), note it and skip. Do not substitute a different source.
- Gap-filling is additive only. Do not delete or overwrite any existing source or guide without user instruction.
