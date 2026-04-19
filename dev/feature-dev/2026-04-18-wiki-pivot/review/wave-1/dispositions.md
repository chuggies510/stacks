# Wave 1 Review Dispositions

## Validation methodology

Applied batch-validation rule (workspace CLAUDE.md Development Practices). Each finding verified by: factual grep/read, empirical test for mechanical claims, consequence scan.

## Disposition table

| ID | Severity | Disposition | Reason | Applied to |
|----|----------|-------------|--------|-----------|
| C-01 | High | APPLY | Empirical test confirms `stat -c %Y` on directory doesn't advance when files inside are edited in-place. A1 gate as written would false-fail every validator run, blocking the entire audit-stack pipeline. | `references/wave-engine.md:199` per-article loop |
| S-01 | Medium | APPLY | Verified: Process step 1b at line 24 and `## Strip Prior Cycle` section at line 37 carry identical guidance. Removed standalone section. | `agents/validator.md` |
| S-02 | Medium | MODIFY | Reviewer counted 3 placements of strip rule. Verified: 2 placements, not 3. Line 40 ("No `[VERIFIED]` markers in the body") is a "don't add" rule, distinct from "strip existing". Removed strip mention from Update paragraph; kept section and line 40. | `agents/article-synthesizer.md:50` |
| S-03 | Medium | APPLY | Verified: Process step 4 and standalone `## Slug Immutability Rule` both state the constraint. Folded escape-hatch clause into step 4; removed standalone section. | `agents/concept-identifier.md` |
| S-04 | Low | APPLY | Verified: `findings-analyst.md:50` uses `id` field name; wave-engine.md said `content-hash`. Aligned to `id` with explicit "full SHA256 of {article-slug}|{finding_type}|{claim}" description. | `references/wave-engine.md:236` |

## Empirical test result (C-01)

```
mkdir /tmp/dirtest && echo hi > /tmp/dirtest/a.md
M1=$(stat -c %Y /tmp/dirtest)  # 1776566753
sleep 2
echo updated > /tmp/dirtest/a.md
M2=$(stat -c %Y /tmp/dirtest)  # 1776566753 — unchanged
```

Confirmed: in-place edits do NOT advance directory mtime. A1 gate rewritten to loop per article file.

## Missed findings (pressure test)

None surfaced via inversion/scale/simplification pressure test beyond the three reviewers' combined output.
