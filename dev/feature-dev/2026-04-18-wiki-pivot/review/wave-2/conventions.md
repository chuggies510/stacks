# Findings: Wave 2 — Conventions

## Summary

| Severity | Count |
|----------|-------|
| High     | 1 |
| Medium   | 2 |
| Low      | 2 |

**Total**: 5 findings

## Findings

### V-1: audit-stack bare scripts/ path (duplicate of C-1)

- **Severity**: High
- **Location**: `skills/audit-stack/SKILL.md:115`
- Deduped with C-1.

### V-2: STACKS_ROOT lookup without path guard

- **Severity**: Medium
- **Location**: `skills/audit-stack/SKILL.md:55` (original)
- **Evidence**: `find ~/.claude/plugins/cache -type d -name "stacks"` (no `-path` guard)
- **Recommendation**: Anchor on scripts/ with path guard, derive STACKS_ROOT by stripping.

### V-3: em dash in catalog-sources prose

- **Severity**: Medium
- **Location**: `skills/catalog-sources/SKILL.md:338` (original)
- **Evidence**: `Sources for failed concepts stay in incoming/ ... — no rollback.`
- **Recommendation**: Replace with period.

### V-4: em dash in audit-stack prose

- **Severity**: Medium
- **Location**: `skills/audit-stack/SKILL.md:166` (original)
- **Recommendation**: Replace with semicolon.

### V-5: hyphen vs en dash

- **Severity**: Low
- **Location**: `skills/catalog-sources/SKILL.md:89`
- **Recommendation**: Defer. Typographic nit.

---

**Last Updated**: 2026-04-18 — initial generation
