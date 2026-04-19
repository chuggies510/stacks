# Findings: Wave 2 — Correctness

## Summary

| Severity | Count |
|----------|-------|
| High     | 3 |
| Medium   | 1 |

**Total**: 4 findings

## Findings

### C-1: audit-stack uses bare scripts/ relative paths

- **Severity**: High
- **Location**: `skills/audit-stack/SKILL.md:115` (original)
- **Evidence**: `  scripts/assert-written.sh "$article" "${DISPATCH_EPOCH}" "validator"`
- **Impact**: Skill runs from library repo root, not plugin dir. Library has no scripts/. All gate calls would fail.
- **Recommendation**: Add SCRIPTS_DIR lookup; prefix all script calls.

### C-2: A4 awk fetch_open counter undercounts

- **Severity**: High
- **Location**: `skills/audit-stack/SKILL.md:206` (original)
- **Evidence**: `/^- id:/ { in_item=1; action=""; status="" }`
- **Impact**: Reset rule fires before count rule on same line; only last item counted correctly. Premature empty-pass declaration.
- **Recommendation**: Combine tally-then-reset into single rule.

### C-3: A5 uses mv instead of cp, breaking feedback flywheel

- **Severity**: High
- **Location**: `skills/audit-stack/SKILL.md:265` (original)
- **Evidence**: `mv "$STACK/dev/audit/findings.md" "$STACK/dev/audit/closed/${audit_date}-findings.md"`
- **Impact**: wave-engine.md:259 is explicit: `cp`, findings.md remains. mv destroys the next W0b's input.
- **Recommendation**: Change mv to cp.

### C-4: W1b pseudocode never populates CONCEPT_SLUGS

- **Severity**: Medium
- **Location**: `skills/catalog-sources/SKILL.md:285` (original)
- **Evidence**: `# Pseudocode for W1b dedup — Claude executes this as inline bash + awk/python`
- **Impact**: Step 8 iterates `for slug in "${CONCEPT_SLUGS[@]}"` — if array never populated, W2 gates silently no-op.
- **Recommendation**: Replace with concrete awk block that populates CONCEPT_SLUGS.

---

**Last Updated**: 2026-04-18 — initial generation
