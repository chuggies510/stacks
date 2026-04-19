# Findings: Wave 1 — Correctness

## Summary

| Severity | Count |
|----------|-------|
| High     | 1 |
| Medium   | 0 |
| Low      | 0 |

**Total**: 1 finding

## Findings

### C-01: A1 gate passes directory path to assert-written.sh; timestamp check is non-functional

- **Severity**: High
- **Location**: `references/wave-engine.md:199`
- **Evidence**: `scripts/assert-written.sh "{stack}/articles/" "${DISPATCH_EPOCH}" "validator"`
- **Impact**: `assert-written.sh` checks `test -s "$path"` (true for any non-empty directory) and `stat -c %Y "$path"` (directory's own mtime). On Linux, editing files in-place inside a directory does not update the directory's mtime. Validator uses `Edit` to mutate existing articles, so directory mtime does not advance past `$DISPATCH_EPOCH`. Every valid validator run produces false `AGENT_WRITE_FAILURE`. Inverse also fails: if the directory's mtime is already ahead of dispatch_epoch (from a prior file creation), the gate passes even when validator wrote nothing.
- **Recommendation**: Replace single directory-path call with a per-article loop. Enumerate expected article slugs from `articles/` before dispatch, then after fan-in run `scripts/assert-written.sh "articles/${slug}.md" "${DISPATCH_EPOCH}" "validator"` for each slug.

---

**Last Updated**: 2026-04-18 — initial generation
