# Findings: Wave 1 — Simplicity

## Summary

| Severity | Count |
|----------|-------|
| High     | 0 |
| Medium   | 3 |
| Low      | 1 |

**Total**: 4 findings

## Findings

### S-01: validator.md — "Strip Prior Cycle" section duplicates Process step

- **Severity**: Medium
- **Location**: `agents/validator.md:37`
- **Evidence**: `## Strip Prior Cycle`
- **Impact**: Strip instruction appears twice: Process step 1b and standalone section. Future editors may update one and miss the other.
- **Recommendation**: Remove the standalone section. The Process step carries the rule.

---

### S-02: article-synthesizer.md — strip rule stated three times

- **Severity**: Medium
- **Location**: `agents/article-synthesizer.md:42`
- **Evidence**: `## Strip-on-Rewrite Rule`
- **Impact**: Strip requirement stated in Output section, standalone section, and Update paragraph. Three owners for one rule.
- **Recommendation**: Keep rule in one place (the standalone section). Remove from Output and Update paragraph.

---

### S-03: concept-identifier.md — "Slug Immutability Rule" section duplicates Process step 4

- **Severity**: Medium
- **Location**: `agents/concept-identifier.md:32`
- **Evidence**: `## Slug Immutability Rule`
- **Impact**: Process step 4 already enforces slug immutability. Standalone section restates it with near-identical language.
- **Recommendation**: Remove standalone section. Fold escape-hatch clause into step 4.

---

### S-04: wave-engine.md — findings item ID field name mismatch

- **Severity**: Low
- **Location**: `references/wave-engine.md:236`
- **Evidence**: `content-hash` as full SHA256
- **Impact**: wave-engine.md calls the ID field `content-hash`; findings-analyst.md schema uses `id`. Reconciliation friction for readers.
- **Recommendation**: Rename to `id` in wave-engine.md to match findings-analyst schema.

---

**Last Updated**: 2026-04-18 — initial generation
