# Findings: Wave 2 — Simplicity

## Summary

| Severity | Count |
|----------|-------|
| High     | 1 |
| Medium   | 3 |
| Low      | 1 |

**Total**: 5 findings

## Findings

### S-1: catalog-sources plugin-path block 3x larger than needed

- **Severity**: High
- **Location**: `skills/catalog-sources/SKILL.md:143` (original)
- **Evidence**: Three separate find-or-fallback blocks for SCRIPTS_DIR, AGENTS_DIR, WAVE_ENGINE
- **Recommendation**: Anchor lookup on scripts/ once, derive others from STACKS_ROOT.

### S-2: argument parsing duplicated verbatim from ingest-sources

- **Severity**: Medium
- **Location**: `skills/catalog-sources/SKILL.md:39`
- **Evidence**: Step 1 is ~52 lines copied from ingest-sources with only the slash-command name changed
- **Recommendation**: Accept as transitional — T15 (#22 cutover) removes ingest-sources, eliminating the duplicate.

### S-3: audit-stack uses bare scripts/ path (duplicate of C-1/V-1)

- **Severity**: Medium
- **Location**: `skills/audit-stack/SKILL.md:115`
- **Recommendation**: Deduped with C-1. Fixed in dispositions.

### S-4: W0 comm step is dead code

- **Severity**: Medium
- **Location**: `skills/catalog-sources/SKILL.md:173`
- **Evidence**: Diffs incoming/ against index.md, but incoming/ paths are by definition not in index
- **Recommendation**: Remove; NEW_SOURCES is just `find incoming/ -type f`.

### S-5: frontmatter descriptions too long

- **Severity**: Low
- **Location**: `skills/catalog-sources/SKILL.md:3`, `skills/audit-stack/SKILL.md:3`
- **Recommendation**: Trim wave enumerations. Defer — not harmful.

---

**Last Updated**: 2026-04-18 — initial generation
