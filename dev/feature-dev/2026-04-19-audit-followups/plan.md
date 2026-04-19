# Plan: audit follow-ups (epic #38)

Spec: `spec.md` in this directory.

## Task DAG and wave schedule

Six implementation tasks. `wave-engine.md` sync + CHANGELOG rollup + final version cut land in Phase 7 close-out (not per-task).

```
Wave 1 (1 agent):    T1 (#33 contract)
                         │
            ┌────────────┼────────────┐
Wave 2 (3 agents):   T2(#34)   T3(#36)   T4(#32)
                                 │         │
Wave 3 (2 agents):          T5(#35)   T6(#37)
```

Wave 2 and Wave 3 dispatch via `feature-dev:parallel-implementation-dispatch`. File ownership cross-checked disjoint within each wave.

**baselineVersion:** `stacks=0.12.1` (snapshot at plan-time). Main session will refuse to bump if `.claude-plugin/plugin.json` version drifts from this baseline before the final cut.

## Per-task ship-version schedule

| Task | Closes sub-issue | Version at commit |
|------|------------------|-------------------|
| T1 | #33 | 0.13.0-alpha.1 |
| T2 | #34 | 0.13.0-alpha.2 |
| T3 | #36 | 0.13.0-alpha.3 |
| T4 | #32 | 0.13.0-alpha.4 |
| T5 | #35 | 0.13.0-alpha.5 |
| T6 | #37 | 0.13.0-alpha.6 |
| close-out | (epic #38) | 0.13.0 |

Main session (not task agents) owns version bumps and CHANGELOG entries at commit time. Agents modify agents/skills/scripts only. This avoids parallel-wave conflict on `plugin.json`, `marketplace.json`, `CHANGELOG.md`.

## Cross-task conventions

**Old failure markers** (5 call sites — enumerated for migration):

```
agents/concept-identifier-orchestrator.md:75:  echo "CATALOG_ORCHESTRATOR_FAILED: W1 gate" >&1
agents/concept-identifier-orchestrator.md:133: echo "CATALOG_ORCHESTRATOR_FAILED: W2 gate" >&1
agents/validator-orchestrator.md:80:  A1_ORCHESTRATOR_FAILED: {N failed}
skills/audit-stack/SKILL.md:132:      A1_ORCHESTRATOR_FAILED: marker
skills/catalog-sources/SKILL.md:230:  CATALOG_ORCHESTRATOR_FAILED: marker
```

All five must migrate to `ORCHESTRATOR_FAILED: wave={wave} reason={short}` in T1. Grep-verify in T1's verifyCommand:

```bash
! grep -rn 'A1_ORCHESTRATOR_FAILED\|CATALOG_ORCHESTRATOR_FAILED' agents/ skills/
```

**Old summary-path refs** (10 call sites — enumerated for migration):

```
agents/concept-identifier-orchestrator.md:140,161,169,172
skills/catalog-sources/SKILL.md:224,227,237,243,247,357
references/wave-engine.md:138,153
```

All ten must migrate from `_orchestrator-summary.json` to `_w1-w2-summary.json` in T1. Validator-orchestrator has no existing summary path to migrate (inline-JSON only today) — T1 adds `_a1-summary.json` writes. References/wave-engine.md is updated in close-out, not T1, so T1's grep excludes it:

```bash
! grep -rn '_orchestrator-summary\.json' agents/ skills/
```

## Tasks

### T1 (#33): unified summary-JSON contract

Closes #33. Ships 0.13.0-alpha.1.

**Files (all pre-existing, edited in place):**
- `agents/validator-orchestrator.md`
- `agents/concept-identifier-orchestrator.md`
- `skills/audit-stack/SKILL.md` (Step 4 A1 gate only — Steps 5, 7 left for T4)
- `skills/catalog-sources/SKILL.md` (Step 6 gate only)

**Mechanism:** per spec `### #33`. Key edits:
1. Both orchestrators write `$STACK/dev/{audit,extractions}/_{wave}-summary.json` with the nested envelope (`schema_version: 1`, `wave`, `status`, `counts{...}`, `epochs{...}`). Receipt line `ORCHESTRATOR_OK: wave={wave}` on stdout. Failure line `ORCHESTRATOR_FAILED: wave={wave} reason={short}`.
2. validator-orchestrator: new summary path `dev/audit/_a1-summary.json`. Today it has no file write — add one.
3. concept-identifier-orchestrator: rename `_orchestrator-summary.json` → `_w1-w2-summary.json`. Restructure flat fields into `counts{}` / `epochs{}`.
4. Main-session gates: parse receipt line, then parse file with nested jq paths. Exact expressions in spec `### #33`.
5. Grep-replace all 5 old failure marker refs and 10 old summary-path refs per above.

**verifyCommand:**
```bash
! grep -rn 'A1_ORCHESTRATOR_FAILED\|CATALOG_ORCHESTRATOR_FAILED' agents/ skills/ && ! grep -rn '_orchestrator-summary\.json' agents/ skills/ && grep -q 'ORCHESTRATOR_OK: wave=a1' agents/validator-orchestrator.md && grep -q 'ORCHESTRATOR_OK: wave=w1-w2' agents/concept-identifier-orchestrator.md && grep -q 'schema_version' agents/validator-orchestrator.md && grep -q 'schema_version' agents/concept-identifier-orchestrator.md
```

### T2 (#34): validator per-batch source union

Closes #34. Ships 0.13.0-alpha.2. Blocked by T1 (reads T1's updated orchestrator file as baseline).

**Files:**
- `agents/validator-orchestrator.md`
- `agents/validator.md` (input contract update: "you receive a scoped source list, not the full tree")

**Mechanism:** per spec `### #34`. Orchestrator pre-dispatch citation-graph bash:

```bash
declare -A SOURCE_MAP
while IFS= read -r src; do
  slug=$(basename "$src" .md)
  SOURCE_MAP[$slug]="$src"
done < <(find "$STACK/sources" -type f -name '*.md' \
  -not -path '*/incoming/*' -not -path '*/trash/*')
```

Per article: extract `sources:` frontmatter paths (basename-normalize) + inline `[source-slug]` refs. Union per batch.

Fallback: if any article in a batch has zero resolvable citations, include full tree for that batch (safe default for `[UNSOURCED]`-heavy articles).

Add worked example to end of agent prompt.

**verifyCommand:**
```bash
grep -q 'SOURCE_MAP' agents/validator-orchestrator.md && grep -q 'citation' agents/validator-orchestrator.md && ! grep -q 'FULL \$STACK/sources/ tree' agents/validator-orchestrator.md
```

### T3 (#36): per-slug `_dedup-{slug}.md` split

Closes #36. Ships 0.13.0-alpha.3. Blocked by T1.

**Files:**
- `agents/concept-identifier-orchestrator.md` (W1b section + W2 dispatch content)
- `agents/article-synthesizer.md` (Input section)

**Mechanism:** per spec `### #36`. W1b after computing `extraction_hash` per unique slug: write both `_dedup.md` (aggregate, unchanged) AND `_dedup-{slug}.md` per unique slug. W2 dispatch passes the per-slug path. article-synthesizer Input updated: "Read your assigned `dev/extractions/_dedup-{slug}.md`. Do not read `_dedup.md` — that is the aggregated audit-trail file."

**verifyCommand:**
```bash
grep -q '_dedup-\${slug}.md\|_dedup-{slug}.md' agents/concept-identifier-orchestrator.md && grep -q '_dedup-{slug}.md\|_dedup-\${slug}\.md' agents/article-synthesizer.md
```

### T4 (#32): A2 + A3 orchestrator wrappers

Closes #32. Ships 0.13.0-alpha.4. Blocked by T1.

**Files:**
- `agents/synthesizer-orchestrator.md` (NEW)
- `agents/findings-analyst-orchestrator.md` (NEW)
- `skills/audit-stack/SKILL.md` (Steps 5 + 7 only — Step 4 is T1's, Step 8.5 is T6's)

**Mechanism:** per spec `### #32`. Both orchestrators use schema v1 envelope from T1. `ARTICLES_PER_AGENT=15`, sharding math identical to validator-orchestrator. Single-shard fast path at `N <= 15`. Above that: partials-file pattern + merge. A2 merge uses a dedicated `synthesizer-merge` sub-agent (not bash) to apply STACK.md tier hierarchy.

audit-stack/SKILL.md Step 5 rewritten to dispatch `synthesizer-orchestrator` (analogous to Step 4's validator-orchestrator dispatch). Step 7 rewritten for `findings-analyst-orchestrator`.

**verifyCommand:**
```bash
test -f agents/synthesizer-orchestrator.md && test -f agents/findings-analyst-orchestrator.md && grep -q 'synthesizer-orchestrator' skills/audit-stack/SKILL.md && grep -q 'findings-analyst-orchestrator' skills/audit-stack/SKILL.md && grep -q 'schema_version' agents/synthesizer-orchestrator.md && grep -q 'schema_version' agents/findings-analyst-orchestrator.md
```

### T5 (#35): W2 wave cap

Closes #35. Ships 0.13.0-alpha.5. Blocked by T3 (wave loop iterates over per-slug files created by T3).

**Files:**
- `agents/concept-identifier-orchestrator.md` (W2 dispatch section only)

**Mechanism:** per spec `### #35`. `W2_WAVE_CAP=25` constant. Wrap W2 dispatch in a wave loop: each wave captures its own `DISPATCH_EPOCH_W2_WAVE`, dispatches ≤25 synthesizers in one Task message, gates each article in the wave with that wave's epoch, increments `n_w2_waves`. Summary JSON `counts.n_w2_waves` populated.

**verifyCommand:**
```bash
grep -q 'W2_WAVE_CAP=25' agents/concept-identifier-orchestrator.md && grep -q 'n_w2_waves' agents/concept-identifier-orchestrator.md && grep -q 'DISPATCH_EPOCH_W2_WAVE' agents/concept-identifier-orchestrator.md
```

### T6 (#37): findings rotation

Closes #37. Ships 0.13.0-alpha.6. Blocked by T4 (audit-stack/SKILL.md baseline must include T4's Step 5/7 edits).

**Files:**
- `agents/findings-analyst.md` (schema v3→v4; carry-forward migration block)
- `scripts/rotate-findings.sh` (NEW)
- `skills/audit-stack/SKILL.md` (new Step 8.5 between A4 and A5; archive-gate addition)

**Mechanism:** per spec `### #37`. Three parts. Script invocation:

```bash
bash "$SCRIPTS_DIR/rotate-findings.sh" "$STACK" "$audit_date"
```

Script reads findings.md, for each terminal-status item computes cycles between `terminal_transitioned_on` and current `audit_date`, rotates items ≥ `ROTATION_CYCLES` (default 3) to `findings-archive.md`. Parse `ROTATION_CYCLES` from STACK.md with same pattern as `MAX_AUDIT_PASSES`.

**verifyCommand:**
```bash
test -x scripts/rotate-findings.sh && grep -q 'schema_version: 4' agents/findings-analyst.md && grep -q 'terminal_transitioned_on' agents/findings-analyst.md && grep -q 'rotate-findings' skills/audit-stack/SKILL.md && bash -n scripts/rotate-findings.sh
```

## Close-out (not a task — runs in Phase 7 Steps 16-17)

- `references/wave-engine.md` sync across all changes (one commit).
- `/workspace-toolkit:a-review` full pass across feature branch.
- `/simplify` pass.
- `CHANGELOG.md` rollup from alpha entries into clean `## [0.13.0]` section.
- `plugin.json` + `marketplace.json` → `0.13.0`. Run `sync-versions.sh` (checked-for-success in CLAUDE.md; stacks has no `sync-versions.sh` — two files bumped in one commit).
- Close epic #38 with final SHA.
- `/stacks:inbox` extractable patterns.
