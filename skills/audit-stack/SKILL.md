---
name: audit-stack
description: |
  Use when the user wants to check a knowledge stack's articles against their
  cited sources. Dispatches the validator agent to fix source-contradictions in
  place and list soft spots (claims not tied to a source), then writes a fresh
  audit report. Incremental by default: re-validates only articles changed since
  their last audit (pass --full to re-check all). Runs from any repo; targets the library configured in
  ~/.config/stacks/config.json, or the current directory when it is itself a library.
---

# Audit Stack

Validate a stack's articles against their cited sources. The validator **fixes** claims that contradict their source in place (so `/stacks:lookup` never serves a known-wrong claim) and records every fix plus every **soft spot** (a claim not tied to any cited source) for the report. No inline marks are stamped in article bodies. Each run is independent: the validator re-checks every article and the report is rebuilt from this run's findings. There is no carry-forward ledger and no multi-pass loop.

The deterministic control flow (resolve, enum, shard, gate, report) lives in `scripts/pipeline/audit.sh` as `prep|gate|finish` phases; state crosses phases through `dev/audit/{run.env,dispatch.tsv}` files, never shell env. This skill dispatches the validator agents between `prep` and `gate` and does the log+commit after `finish`.

## Step 0: Telemetry

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
SKILL_NAME="stacks:audit-stack" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
```

## Step 1: Prep — resolve, enum, shard (`audit.sh prep`)

`audit.sh prep` does everything deterministic in one call: resolve+cd the library, check the stack exists and has articles, enumerate `articles/*.md`, **skip the ones unchanged since their last audit** (incremental — see below), shard the rest into `CAP=5` batches, and write the run-state files (`dev/audit/dispatch.tsv`, `dev/audit/run.env` with `RUN_ID`). It prints how many were skipped vs. dispatched, the manifest path, the sources dir, the stack root, and the `RUN_ID` the dispatch below passes to each agent.

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
bash "$STACKS_ROOT/scripts/pipeline/audit.sh" prep $ARGUMENTS
```

**Incremental skip.** prep compares each article's current content hash (`git hash-object`) against `dev/audit/verified.tsv` (the hash finish recorded at its last successful audit). An unchanged article re-validates to the same result, so it is skipped to save the validator's per-article token cost. A first run (no verified.tsv) audits everything; the stack self-migrates on that pass. Pass **`--full`** (`/stacks:audit-stack {stack} --full`) to ignore verified.tsv and re-check every article — do this after the validator's own logic changes, or after editing a cited **source** in place (the hash keys on the article, not its sources, so a source edited without re-cataloging the article is the one change the skip cannot see; the "sources are immutable" convention normally rules this out, and re-cataloging a source rewrites the article anyway → its hash moves → re-audited). Against article changes the skip is safe by construction: any hash miss falls through to auditing, so it never serves a changed article as still-valid.

**If prep prints `NOTHING_TO_AUDIT`** (every article unchanged): skip Steps 2–4 entirely and jump to Step 5 (`audit.sh finish`) — finish refreshes the report, carries the skipped articles' soft spots forward, and re-stamps verified.tsv. There is nothing to dispatch or gate.

A non-zero exit (no stack name, stack not found, no articles, or an unknown flag) prints the reason and stops the run. Otherwise note the printed `RUN_ID`, manifest, sources, and stack-root paths — they feed the dispatch.

## Step 2: Read STACK.md

Read `$STACK/STACK.md` (the stack root is in prep's output) for the source-hierarchy section. The validator needs it to resolve conflicts when two sources disagree (higher-tier source wins; the losing claim is fixed in place to match it — no inline mark is stamped).

## Step 3: Dispatch the validator over the article batches

`prep` already sharded the articles into `CAP=5` batches — kept modest on purpose: each validator re-reads every article in its slice *plus* the sources each claim cites, so a large slice both risks "prompt too long" and pollutes one context with many articles' claims (a claim from article A gets checked against article B's source). Per-article isolation matters more than minimizing dispatch count. (Change the cap in `audit.sh`'s `CAP=` constant, not here.)

Read the manifest `dev/audit/dispatch.tsv` (the `Manifest:` path from prep) — each row is `batch_tag<TAB>slug<TAB>article_path`. **In a single message, emit one `Agent` tool call per distinct `batch_tag`**, `subagent_type` = `stacks:validator`. Parallel dispatch — never sequential.

Dispatch each batch agent with `run_in_background: true` so the session stays responsive during the multi-minute validator runtime; the harness delivers a completion notification per agent. This phase is a barrier: do not run Step 4 (`audit.sh gate`) until every dispatched agent for this wave has reported completion. Backgrounding preserves the barrier (you still wait for all agents) while keeping the session interactive and letting you interleave other work.

Each agent prompt names:

- its assigned **article paths** (column 3 of that batch's manifest rows),
- the stack's sources directory `$STACK/sources/` (the agent reads what each claim cites; it excludes `sources/incoming/` and `sources/trash/`),
- the source-hierarchy context from STACK.md,
- `$STACK/index.md`'s `## Articles` scope map (when present) — the `slug — scope` routing lines for every article in the stack, not just this batch; feeds the validator's structural lumping/fragmentation advisory (stacks#106), returned in text only,
- the stack root `$STACK`,
- its **`BATCH_TAG`** (the `batch_tag` value: `0`, `1`, …),
- the **`RUN_ID`** from prep's output (echoed verbatim in each `VALIDATED` receipt row).

The validator strips prior-cycle marks, fixes source-contradictions in place, sets `last_verified` to today, writes one `VALIDATED<TAB>{slug}<TAB>{RUN_ID}` receipt row per assigned article (clean articles included) plus any `CORRECTION`/`SOFTSPOT` lines, to `$STACK/dev/audit/_audit-${BATCH_TAG}.md`.

## Step 4: Gate — every dispatched article must be receipted (`audit.sh gate`)

After all validators return, gate the batch. `audit.sh gate` re-reads the run-state from disk (the `RUN_ID` freshness floor and the manifest), runs `gate-batch.sh` (write-or-fail + `audit-findings` shape = a `VALIDATED` receipt row exists) on every expected `_audit-<tag>.md`, then `check-coverage.sh --verdict VALIDATED` (reconciles the dispatched slugs against the slug column of the `VALIDATED` receipt rows — the `--verdict` filter skips the `CORRECTION`/`SOFTSPOT` rows that reuse the slug column). A dropped, duplicated, unknown, or missing receipt fails **by name**.

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
bash "$STACKS_ROOT/scripts/pipeline/audit.sh" gate $ARGUMENTS
```

A non-zero exit means a validator did not process an article it was assigned (no receipt row) or wrote no file — surface the named failure and stop. This is the per-article coverage the old `last_verified == today` date-gate could not prove.

## Step 4.5: Local-validation shadow + advisory verify (verify-and-fix rollout, opt-in — #109)

**Runs only when `STACKS_LOCAL_SHADOW=1` is set.** Default runs skip it. This is the validation analog of the extraction advisory (catalog Step 5.5): it grades whether the cheap local tier could do the per-claim validation judgment behind the harness — the recipe is the cheap tier emits one verdict per claim, the deterministic **`claim-citation-gate`** owns citation-presence (structurally coercing a CLEAN on an uncited claim to `INVALID/uncited-clean`, closing the S24 item-6 miss), and the cloud **`validation-verifier`** owns the content judgment (does the cited source actually support the claim). **The cloud `validator`'s in-place fixes from Steps 3–4 are authoritative and untouched; this only observes.** Runs after `gate` and before `finish` clears `dispatch.tsv`.

First the local per-claim pass (reads the transient `dispatch.tsv`, so it must run before `finish`; writes one per-batch claim file + a `batches.tsv` dispatch manifest):

```bash
if [ "${STACKS_LOCAL_SHADOW:-0}" = "1" ]; then
  STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
  bash "$STACKS_ROOT/dev/experiments/model-tier/harness/shadow-validate-run.sh" {stack} || echo "validation shadow returned non-zero — non-fatal, continuing"
fi
```

Non-fatal by design (Ollama unreachable → every article logs a failure and the run proceeds). Read the `SHADOW_VALIDATE_SUMMARY` line for the articles/claims/failed counts, and the dispatch manifest at `$STACKS_ROOT/dev/experiments/model-tier/live-diffs/validate/batches.tsv` (rows: `batch_tag<TAB>batchfile`).

Then the advisory verify: **reset the grade dir** (`rm -rf "$STACKS_ROOT/dev/experiments/model-tier/live-diffs/validation-verify" && mkdir -p "$STACKS_ROOT/dev/experiments/model-tier/live-diffs/validation-verify"`), then for each `batches.tsv` row dispatch one **`stacks:validation-verifier`** agent (cloud sonnet, ≤25 per message). Give each agent absolute paths, scope pinned to: the batch claim file (column 2 — each claim's text, the local-quoted excerpt, and the gated local verdict), the audited articles under `{LIBRARY}/{stack}/articles/` and the stack's real sources `{LIBRARY}/{stack}/sources/` (the agent forms its OWN authoritative verdict from the real source, since the local-quoted excerpt may be paraphrased or mis-retrieved), and the grade JSON to write at `$STACKS_ROOT/dev/experiments/model-tier/live-diffs/validation-verify/{batch_tag}.json`. It never edits any article or verdict. After the wave returns, aggregate:

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
bash "$STACKS_ROOT/dev/experiments/model-tier/harness/validation-verify-summary.sh" \
  "$STACKS_ROOT/dev/experiments/model-tier/live-diffs/validation-verify" || true
```

Read the `poison recall` and `false-correction rate` lines — a poison recall breach (a claim that overstates/contradicts its source, called CLEAN) is the dangerous class nothing downstream catches; a high false-correction rate means the local tier is trimming truthful claims (often from mis-retrieving the source passage). Both must clear before validation could flip to a local authoritative tier. Advisory only — `finish` proceeds regardless.

## Step 5: Audit report (`audit.sh finish`)

`audit.sh finish` aggregates the `CORRECTION`/`SOFTSPOT` rows across the dispatched batch files, rebuilds `dev/audit/report.md` (this run's corrections + soft spots), merges `dev/audit/soft-spots.tsv` (the `/stacks:enrich-stack` input — carrying the skipped articles' prior soft spots forward, since an incremental run only re-checks changed articles), re-stamps `dev/audit/verified.tsv` (every article's current hash, so the next prep can skip the unchanged ones), prints an `AUDIT_SUMMARY: articles=… skipped=… corrections=… softspots=…` line, then removes the transient run files. Runs after a `NOTHING_TO_AUDIT` prep too (carries all soft spots, re-stamps hashes, writes a 0-audited report).

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
bash "$STACKS_ROOT/scripts/pipeline/audit.sh" finish $ARGUMENTS
```

Read the printed `AUDIT_SUMMARY` counts — they feed the log entry and commit message below.

## Step 6: Log and commit

Prepend an entry to `$STACK/log.md` using the counts from `AUDIT_SUMMARY`:

```markdown
## [YYYY-MM-DD] audit-stack
Validated={articles} Corrections={corrections} SoftSpots={softspots}. Report: dev/audit/report.md
```

Then commit the corrected articles and the report. Substitute `{stack}` and the counts — shell state does not survive between these blocks, so re-resolve the library here rather than relying on a `$STACK`/`$LIBRARY` from an earlier step:

```bash
STACKS_ROOT="${CLAUDE_PLUGIN_ROOT:-$(jq -r '.extraKnownMarketplaces.stacks.source.path // empty' "$HOME/.claude/settings.json" 2>/dev/null)}"
LIBRARY=$(bash "$STACKS_ROOT/scripts/resolve-library.sh") && cd "$LIBRARY" || exit 1
git add "{stack}/articles/" "{stack}/dev/audit/report.md" "{stack}/dev/audit/soft-spots.tsv" "{stack}/dev/audit/verified.tsv" "{stack}/log.md"
git commit -m "audit({stack}): corrections={corrections} soft-spots={softspots}"
```

Present a summary to the user: articles validated, corrections applied, soft-spot count, and the report path. If corrections were applied, name the most-corrected articles so the operator can eyeball the auto-edits (they are also visible in the commit diff). If soft spots are high, point at the report. Also surface any **Structural advisory** notes the validators returned in their text (possible lumping/fragmentation across articles, stacks#106): these are advisory-only and are NOT written to `report.md`, so relay them to the operator here or they are lost.
