---
session: 20
---

# stacks Active Context

## Current state
- Plugin at **0.51.0**. This session shipped 0.50.0 → 0.50.1 → 0.51.0.
- Open stacks issues: **1** (#70, deliberately open — see Next priority).
- All fan-out pipelines (catalog, audit, enrich) run through `scripts/pipeline/*.sh` phases; no cross-block env.
- Gap-queue (`lookup-misses.sh`) is now per-library + 30-day recency scoped; telemetry records the resolved library path.

## Open thread

None, closed clean. The two-phase plan (`dev/plans/2026-07-07-codex-fixes-and-73-plan.md`) executed end to end: all 7 tasks + both checkpoints done, every task carried a red-when-removed check that was verified, and #54/#93/#86/#73 are closed.

## Next priority

**#70** is the only open stacks issue and is intentionally an anchor: its fix is cross-repo, **ChuggiesMart#596** (a workspace-toolkit `/start` library-news hook — reads `~/.config/stacks/config.json`, runs one stateless `git log --since=7.days --diff-filter=A` probe against the library, emits one line on recent article adds). Zero stacks code; close #70 when #596 ships. Full design: `docs/superpowers/specs/2026-07-07-library-discovery-and-gap-queue-design.md`. Otherwise the singleton backlog is empty — pick new work as it arrives.

Also filed this session: **ChuggiesMart#597** — workspace-toolkit `/start` pin (`.claude/.session-current`) is git-tracked and commits a stale session number (bit this very /stop; see Decisions).

---

## CONTEXT HANDOFF - 2026-07-07 (Session 20)

### Session summary
Resolved the remaining stacks singleton backlog across three releases. Opened by shipping **0.50.0** (`e77cf59`) — three independent backlog issues: maintenance skills field-scoped (#54), a pure-reference source can pass the catalog W1 gate via a `# no-concepts:` sentinel (#93), and an empty stack cold-starts its gap list from `STACK.md` scope bullets (#86). Ran an adversarial **codex review** of that diff (xhigh, `danger-full-access`) which found 4 real holes (F1 High, F2 High, F3 Medium, F4 Low) — all confirmed against source — so I reopened #54 and #93 and wrote a two-phase plan (`f51360c`). Then executed it in `/build auto`, TDD, one commit per checkpoint:

- **0.50.1** (`b6dc99d`, patch, re-closed #54/#93, hardened #86): sentinel must be the file's sole non-blank line (F1, else real content smuggled past the gate = silent data loss); new-stack scaffold consolidated into one Bash block + re-derives names per block so it survives the harness per-block env reset when run from a field repo (F2); using-stacks routing prose corrected — every skill runs from any repo, library resolved from config not cwd (F4); enrich `scope_topics()` excludes by heading name at any depth, not the first `### ` (F3).
- **0.51.0** (`a381879`, minor, closed #73): lookup records the resolved library in telemetry; `lookup-misses.sh` filters by library + a 30-day recency window (ISO-string cutoff, no `date -d` trap); enrich prep passes the library through. Plus two folded convert-sources nits — multi-sheet `.xlsx` → one CSV sidecar per sheet via openpyxl (libreoffice was dropping all but the active sheet); each unconvertible input named in the run summary.

Full suite 119/119 green (+9 new bats), enrich self-check 12/12. Each fix's red-when-removed check was actually run (old parser proved red; per-block simulation proved new-stack; filter-stripped copies proved cross-library/stale leak).

### Chat
S20-codex-fixes-gap-queue

### Changes made
| Change | Status |
|--------|--------|
| 0.50.0 — #54/#93/#86 (3 singletons) `e77cf59` | shipped, closed |
| Plan doc — codex F1-F4 + #73 `f51360c` | committed |
| 0.50.1 — 4 codex fixes, re-close #54/#93 `b6dc99d` | shipped, closed |
| 0.51.0 — #73 gap-queue + convert nits `a381879` | shipped, closed |
| Durable reconcile: system-patterns (field model, gap-queue), tech-context (openpyxl) | this /stop |

### Knowledge extracted
- `system-patterns.md`: folded the **field-usage model** into the new-stack flow line (build/maintain skills resolve the library from config and run from any repo — the reversed-#54 durable fact) + the per-block-reset hardening; rewrote the lookup-miss weak-spot to shipped state (per-library + recency scoping shipped, durable resolved-ledger still deferred).
- `tech-context.md`: added `openpyxl` (multi-sheet xlsx) to the convert-sources dependency list; libreoffice reframed as the single-sheet fallback.

### Decisions recorded
- **Executed the codex fixes directly rather than re-delegating to background agents.** Codex found 4 holes in the prior background-agent round; these were small correctness fixes on reopened issues, so I implemented them in-session with red-when-removed checks instead of risking a fresh round of agent-introduced holes.
- **Session number: used detect's 20, overrode the stale pin (19).** The tracked `.session-current` pin contradicted an already-committed S19 handoff; the pin-precedence rule assumes the pin is fresher, but here it would lower the number and clobber S19. Filed ChuggiesMart#597 for the root cause.
- **openpyxl (via uv) as the primary multi-sheet xlsx path**, libreoffice as fallback: deterministic, runs without a libreoffice install, and libreoffice CSV export is single-sheet only.

### Next session priority
#70 stays open as the anchor for **ChuggiesMart#596** (workspace-toolkit `/start` library-news hook, zero stacks code) — close #70 when #596 ships. **ChuggiesMart#597** (tracked-pin bug) filed this session. stacks singleton backlog otherwise empty.

### Open issues
1 open (#70, intentional anchor). No stale specs.
