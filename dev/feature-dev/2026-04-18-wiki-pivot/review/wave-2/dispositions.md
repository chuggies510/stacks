# Wave 2 Review Dispositions

14 findings across 3 reviewers. Deduplication: C-1 ≡ V-1 ≡ S-3 (same issue, 3 lenses). Net: 12 distinct findings.

## Disposition table

| ID | Sev | Disp | Reason | Applied to |
|----|-----|------|--------|-----------|
| C-1 / V-1 / S-3 | High | APPLY | Empirically confirmed: library repo has no scripts/. audit-stack Step 2 now sets SCRIPTS_DIR via path-guarded find; all 5 script calls replaced with `$SCRIPTS_DIR/` prefix. | `skills/audit-stack/SKILL.md` Step 2 + replace-all |
| C-2 | High | APPLY | Awk rule-ordering analysis confirmed reset-before-count race. Merged into single `^- id:/` rule that tallies prior item first, then resets. | `skills/audit-stack/SKILL.md` Step 8 awk block |
| C-3 | High | APPLY | Cross-checked with `references/wave-engine.md:259` which explicitly uses `cp` with comment "findings.md remains at dev/audit/findings.md as the baseline for the next cycle". mv would break W0b on next catalog-sources run. | `skills/audit-stack/SKILL.md` Step 9 |
| C-4 | Med | APPLY | Pseudocode never populated CONCEPT_SLUGS. Replaced with concrete awk+bash that groups by slug, merges source_paths, writes `_dedup.md`, and populates the array. | `skills/catalog-sources/SKILL.md` Step 7 |
| S-1 | High→Med | APPLY | Collapsed 3 find blocks to 1 anchor + 2 derivations. Matches the now-fixed audit-stack Step 2 pattern. | `skills/catalog-sources/SKILL.md` Step 3 |
| S-2 | Med | DEFER | Argument parsing verbatim from ingest-sources. T15 (#22) removes ingest-sources at cutover, eliminating the duplicate within this epic. No maintenance trap. | (deferred) |
| S-4 | Med | APPLY | `comm` was dead code: incoming/ paths are never in index.md. Replaced with single find. | `skills/catalog-sources/SKILL.md` Step 4 |
| S-5 | Low | DEFER | Frontmatter descriptions long but not harmful. | (deferred) |
| V-2 | Med | APPLY | Path-guarded find on scripts/ + strip suffix pattern is robust to other plugins having `stacks/` subdirs. | `skills/audit-stack/SKILL.md` Step 2 (same edit as C-1) |
| V-3 | Med | APPLY | Em dash in prose line 338 replaced with period. Also fixed two em dashes I introduced during S-4 edit (lines 162, 205). | `skills/catalog-sources/SKILL.md` |
| V-4 | Med | APPLY | Em dash at line 166 replaced with semicolon. | `skills/audit-stack/SKILL.md` |
| V-5 | Low | DEFER | Typographic nit. | (deferred) |

## Missed findings (pressure test)

None surfaced beyond the combined reviewer output.

## Post-fix verification

- Both verifyCommands pass
- Grep confirms no bare `scripts/(assert-written|wikilink-pass)` calls remain in audit-stack
- Grep confirms em dashes remain only in structural heading labels (`## Step N — Title`), not prose
