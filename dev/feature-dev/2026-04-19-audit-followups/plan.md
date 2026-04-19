# Plan: audit follow-ups (epic #38)

Spec: `spec.md` in this directory.

## Task DAG and wave schedule

Five implementation tasks in 3 waves. T5 (W2 wave cap) folded into T3 since both edit the same W2 dispatch code region in `concept-identifier-orchestrator.md`. `wave-engine.md` sync + CHANGELOG rollup + final version cut land in Phase 7 close-out (not per-task).

```
Wave 1 (1 agent):  T1 (#33 contract)
                        │
             ┌──────────┼──────────┐
Wave 2 (3):  T2(#34 source-sharding)  T3(#36+#35 dedup-split+wave-cap)  T4(#32 A2/A3-wrappers)
                                                                            │
Wave 3 (1):                                                        T5(#37 rotation)
```

Wave 2 dispatches via `feature-dev:parallel-implementation-dispatch`. Wave 3 is a single task (T5 blocked by T4 only). File ownership disjoint within Wave 2.

**baselineVersion:** `stacks=0.12.1` (snapshot at plan-time). Main session refuses to bump if `.claude-plugin/plugin.json` drifts from this baseline before the final cut.

## Per-task ship-version schedule

| Task | Closes sub-issue(s) | Version at commit |
|------|---------------------|-------------------|
| T1 | #33 | 0.13.0-alpha.1 |
| T2 | #34 | 0.13.0-alpha.2 |
| T3 | #36 + #35 | 0.13.0-alpha.3 |
| T4 | #32 | 0.13.0-alpha.4 |
| T5 | #37 | 0.13.0-alpha.5 |
| close-out | (epic #38) | 0.13.0 |

**Main-session commit protocol per task (not agent work):**

1. Bump **both** `.claude-plugin/plugin.json` AND `.claude-plugin/marketplace.json` to the task's `shipVersion`. Dual bump required by stacks CLAUDE.md; stacks has no `sync-versions.sh`.
2. Append a CHANGELOG stub under `## [0.13.0-alpha.N] (unreleased)` header: 1-3 lines naming the change and sub-issue closed. Close-out rolls all alpha stubs into the final `## [0.13.0]` section.
3. Stage only `metadata.files` from the task plus the two plugin JSON files and `CHANGELOG.md`. Do not `git add -A`.
4. Commit with format `feat({subsystem}): {short-description} ({shipVersion}, #38, task T{N}, closes #{sub-issue})`. Example: `feat(orchestrators): unified summary-JSON contract schema_version=1 (0.13.0-alpha.1, #38, task T1, closes #33)`. `subsystem` = primary changed dir under `agents/`, `skills/`, or `scripts/`.
5. Within Wave 2, commits land in T-ID order (T2 before T3 before T4) regardless of agent-return order. Main session buffers parallel-agent output, then commits serially by T-ID.
6. Close the sub-issue(s) via `workspace-toolkit/references/issue-close-protocol.md` with the commit SHA.

## Cross-task conventions

**Old failure markers** (5 call sites, enumerated for migration):

```
agents/concept-identifier-orchestrator.md:75:  echo "CATALOG_ORCHESTRATOR_FAILED: W1 gate" >&1
agents/concept-identifier-orchestrator.md:133: echo "CATALOG_ORCHESTRATOR_FAILED: W2 gate" >&1
agents/validator-orchestrator.md:80:           A1_ORCHESTRATOR_FAILED: {N failed}
skills/audit-stack/SKILL.md:132:               A1_ORCHESTRATOR_FAILED: marker
skills/catalog-sources/SKILL.md:230:           CATALOG_ORCHESTRATOR_FAILED: marker
```

All five migrate to `ORCHESTRATOR_FAILED: wave={wave} reason={short}` in T1. Grep gate:

```bash
! grep -rn 'A1_ORCHESTRATOR_FAILED\|CATALOG_ORCHESTRATOR_FAILED' agents/ skills/
```

**Old summary-path refs** (10 call sites, enumerated for migration):

```
agents/concept-identifier-orchestrator.md:140,161,169,172
skills/catalog-sources/SKILL.md:224,227,237,243,247,357
references/wave-engine.md:138,153
```

T1 migrates the agents/ and skills/ refs (8 sites). `references/wave-engine.md` (2 sites) updated in close-out. T1 verify excludes references/:

```bash
! grep -rn '_orchestrator-summary\.json' agents/ skills/
```

## Tasks

### T1 (#33 unified summary-JSON contract)

Closes #33. Ships 0.13.0-alpha.1.

**Files (all pre-existing):**
- `agents/validator-orchestrator.md`
- `agents/concept-identifier-orchestrator.md`
- `skills/audit-stack/SKILL.md` (Step 4 A1 gate only; Steps 5+7 left for T4)
- `skills/catalog-sources/SKILL.md` (Step 6 gate only)

**Mechanism (per spec `### #33`):**
1. Both orchestrators write `$STACK/dev/{audit,extractions}/_{wave}-summary.json` with nested envelope: `{schema_version: 1, wave, status, counts, epochs}`. Receipt line `ORCHESTRATOR_OK: wave={wave}` on stdout; failure line `ORCHESTRATOR_FAILED: wave={wave} reason={short}`.
2. validator-orchestrator: add NEW summary-file write at `dev/audit/_a1-summary.json`. Today it only returns inline JSON; add a disk write.
3. concept-identifier-orchestrator: rename existing `_orchestrator-summary.json` → `_w1-w2-summary.json` and restructure flat fields into `counts{}` / `epochs{}`.
4. Main-session gates: parse receipt line, then read summary file with nested jq paths per spec.
5. Grep-replace all 5 failure markers and 8 summary-path refs (within agents/ + skills/) per the enumerated lists above.

**verifyCommand:**
```bash
! grep -rn 'A1_ORCHESTRATOR_FAILED\|CATALOG_ORCHESTRATOR_FAILED' agents/ skills/ && ! grep -rn '_orchestrator-summary\.json' agents/ skills/ && grep -q 'ORCHESTRATOR_OK: wave=a1' agents/validator-orchestrator.md && grep -q 'ORCHESTRATOR_OK: wave=w1-w2' agents/concept-identifier-orchestrator.md && grep -q 'schema_version' agents/validator-orchestrator.md && grep -q 'schema_version' agents/concept-identifier-orchestrator.md
```

### T2 (#34 validator per-batch source union)

Closes #34. Ships 0.13.0-alpha.2. Blocked by T1.

**Files:**
- `agents/validator-orchestrator.md`
- `agents/validator.md` (input-contract update: "scoped source list, not full tree")

**Mechanism (per spec `### #34`):** orchestrator pre-dispatch bash builds slug→path map from `sources/` (excluding `incoming/`, `trash/`). Per article: extract `sources:` frontmatter paths (basename-normalize) + inline `[source-slug]` refs. Union per batch. Each validator receives only its batch's cited-source paths. Fallback: batch with any article having zero resolvable citations falls back to full tree (safe for `[UNSOURCED]`-heavy articles). Add worked example to end of agent prompt.

**verifyCommand (positive checks; no reliance on removed exact-phrase):**
```bash
grep -q 'SOURCE_MAP' agents/validator-orchestrator.md && grep -q 'citation' agents/validator-orchestrator.md && grep -qE 'zero (resolvable )?citations|UNSOURCED' agents/validator-orchestrator.md
```

### T3 (#36 per-slug dedup + #35 W2 wave cap)

Closes #36 and #35. Ships 0.13.0-alpha.3. Blocked by T1.

**Files:**
- `agents/concept-identifier-orchestrator.md` (W1b writes per-slug files; W2 dispatch wrapped in wave loop)
- `agents/article-synthesizer.md` (Input section updated)

**Mechanism (per spec `### #36` + `### #35`):**
1. W1b after computing `extraction_hash` per unique slug: write both `_dedup.md` (aggregate, unchanged; operator audit trail) AND `_dedup-{slug}.md` per unique slug.
2. W2 dispatch wrapped in wave loop: `W2_WAVE_CAP=25`, each wave captures its own `DISPATCH_EPOCH_W2_WAVE`, dispatches ≤25 synthesizers in one Task message, gates each article in the wave with that wave's epoch. Increment `n_w2_waves`. Summary JSON `counts.n_w2_waves` populated.
3. W2 dispatch task-content passes the per-slug file path (not aggregated). article-synthesizer Input updated: "Read your assigned `dev/extractions/_dedup-{slug}.md`. Do not read `_dedup.md` (aggregated audit-trail file)."

**verifyCommand:**
```bash
grep -qE '_dedup-(\{slug\}|\$\{slug\}|\$slug)\.md' agents/concept-identifier-orchestrator.md && grep -qE '_dedup-(\{slug\}|\$\{slug\}|\$slug)\.md' agents/article-synthesizer.md && grep -q 'W2_WAVE_CAP=25' agents/concept-identifier-orchestrator.md && grep -q 'n_w2_waves' agents/concept-identifier-orchestrator.md && grep -q 'DISPATCH_EPOCH_W2_WAVE' agents/concept-identifier-orchestrator.md
```

### T4 (#32 A2/A3 orchestrator wrappers)

Closes #32. Ships 0.13.0-alpha.4. Blocked by T1.

**Files (2 NEW + 1 edit):**
- `agents/synthesizer-orchestrator.md` (NEW)
- `agents/findings-analyst-orchestrator.md` (NEW)
- `skills/audit-stack/SKILL.md` (Steps 5 + 7 only; Step 4 is T1's, Step 8.5 is T5's)

**Mechanism (per spec `### #32`):** both orchestrators use schema v1 envelope from T1. A2 `ARTICLES_PER_AGENT=30` (synthesizer has no sources-tree ceiling); A3 `ARTICLES_PER_AGENT=15` (same as A1). Sharding math `ceil(N/5)` capped at the per-orchestrator cap. Single-shard fast path when `N` fits one shard; skip partials. A2 reduce dispatches the existing `synthesizer` agent a second time with task content "merge these `_a2-partial-*.md` files with STACK.md tier hierarchy and write the three final files". No new `synthesizer-merge` agent. A3 reduce is bash-merge by item `id` (sha256 already stable) with status-precedence (terminal > open, never regresses).

audit-stack Step 5 rewritten to dispatch `synthesizer-orchestrator` analogous to Step 4's `validator-orchestrator` dispatch. Step 7 rewritten for `findings-analyst-orchestrator`.

**Agent frontmatter requirements (stacks CLAUDE.md convention):** both NEW agent files must have YAML frontmatter with `name`, `tools` (comma-separated, minimally `Task, Bash, Glob, Read`), `model: sonnet`, and `description`. Prompt body must include 3+ worked examples. Match `agents/validator-orchestrator.md` structure.

**verifyCommand:**
```bash
test -f agents/synthesizer-orchestrator.md && test -f agents/findings-analyst-orchestrator.md && grep -q '^tools:' agents/synthesizer-orchestrator.md && grep -q '^tools:' agents/findings-analyst-orchestrator.md && grep -q '^model:' agents/synthesizer-orchestrator.md && grep -q '^model:' agents/findings-analyst-orchestrator.md && grep -c '^## Example' agents/synthesizer-orchestrator.md | awk '$1>=3' | grep -q . && grep -c '^## Example' agents/findings-analyst-orchestrator.md | awk '$1>=3' | grep -q . && grep -q 'synthesizer-orchestrator' skills/audit-stack/SKILL.md && grep -q 'findings-analyst-orchestrator' skills/audit-stack/SKILL.md && grep -q 'schema_version' agents/synthesizer-orchestrator.md && grep -q 'schema_version' agents/findings-analyst-orchestrator.md
```

### T5 (#37 findings rotation)

Closes #37. Ships 0.13.0-alpha.5. Blocked by T4 (audit-stack SKILL.md baseline must include T4's Step 5/7 edits).

**Files:**
- `agents/findings-analyst.md` (schema v3 → v4; v3→v4 carry-forward migration block)
- `scripts/rotate-findings.sh` (NEW; **run `chmod +x` after creation**)
- `skills/audit-stack/SKILL.md` (new Step 8.5 between A4 and A5; archive-gate addition)

**Mechanism (per spec `### #37`):**
1. findings-analyst frontmatter schema bump to v4; add `terminal_transitioned_on: YYYY-MM-DD` item field.
2. v3→v4 migration block in findings-analyst carry-forward section (same pattern as v2→v3 at line 113): missing `terminal_transitioned_on` on a terminal item is set to current `audit_date` before writing the v4 item.
3. `scripts/rotate-findings.sh` takes `$STACK` and `$audit_date` as args; reads findings.md; for terminal items computes cycles since `terminal_transitioned_on`; rotates items ≥ `ROTATION_CYCLES` (default 3, grepped from STACK.md same as `MAX_AUDIT_PASSES`) to `findings-archive.md`. Missing field → cycles=0 → no rotation (safe first-run).
4. audit-stack new Step 8.5 invocation: `DISPATCH_EPOCH=$(date +%s); bash "$SCRIPTS_DIR/rotate-findings.sh" "$STACK" "$audit_date"; [[ rotated>0 ]] && "$SCRIPTS_DIR/assert-written.sh" "$STACK/dev/audit/findings-archive.md" "${DISPATCH_EPOCH}" "rotate-findings"`.
5. `chmod +x scripts/rotate-findings.sh` after creation. Write tool produces 0644, `test -x` gate will fail otherwise.

**verifyCommand:**
```bash
test -x scripts/rotate-findings.sh && grep -q 'schema_version: 4' agents/findings-analyst.md && grep -q 'terminal_transitioned_on' agents/findings-analyst.md && grep -q 'rotate-findings' skills/audit-stack/SKILL.md && bash -n scripts/rotate-findings.sh
```

## Close-out (runs in Phase 7 Steps 16-17, not a task)

1. `references/wave-engine.md` sync across all changes (one commit).
2. `/workspace-toolkit:a-review` full pass across feature branch.
3. `/simplify` pass.
4. `CHANGELOG.md` rollup: collapse alpha stubs into final `## [0.13.0]` section.
5. Bump `plugin.json` + `marketplace.json` → `0.13.0` (dual file, no alpha).
6. Close epic #38 with final SHA.
7. `/stacks:inbox` extractable patterns.
