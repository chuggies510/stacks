# Library discovery (#70) + lookup-miss gap queue (#73) — design

Date: 2026-07-07 · Session 20 · Status: approved (plan only, no code this session)

Two related stacks issues, both deliberately scoped to the laziest MVP (minimum
viable product — the smallest thing that removes the pain) that kills the pain.
Article = one curated wiki entry; library = the knowledge repo; stack = one topic
area inside it; lookup = the query skill; enrich = the source-acquisition skill.

---

## #73 — Lookup-miss gap queue: minimal (recency + library-id), plus two folded ingest nits

### Pain
A "miss" is a `/stacks:lookup` that searched a stack but matched no article — live
demand the library could not answer. The manual batch `enrich-stack` path mines
these from a global, append-only telemetry log (`~/.chuggiesmart/telemetry.jsonl`)
filtered by **stack name only**. Two consequences:

1. **Cross-library contamination.** The record has no library id, so two libraries
   each with a stack named `llm` feed each other's miss list.
2. **Stale re-mining.** No recency cutoff and no resolution marker, so an
   already-answered query is re-searched on every batch run, forever.

The live auto-enrich path (0.37.0) already sidesteps telemetry (it passes
`--query` directly); only the manual batch path still reads it, so this fix is
scoped to that path.

### Design (2 files for the queue fix)

| Unit | Change | Why |
|------|--------|-----|
| `skills/lookup/SKILL.md` | Its telemetry call already resolves `LIBRARY`; add it to the EXTRA json so each lookup record carries `library` (absolute path). | `telemetry.sh` merges EXTRA verbatim — no change to the shared recorder. Attributes every future miss to a specific library. |
| `scripts/lookup-misses.sh` | Add `select(.library == $lib)` and a recency window `select(.ts >= cutoff)` (default **30 days**, a named constant). `enrich.sh prep` passes the resolved library path + window. | Library filter kills contamination; recency window bounds staleness without a resolution-marker subsystem. |

**Backward compatibility:** pre-fix records have no `.library` field — they fall
outside the library filter and age out of the recency window. No migration, no
backfill.

**Deferred (the "full" option, not built now):** a durable library-local gap queue
(`dev/gaps/lookup.jsonl` with created/resolved status and later-hit suppression).
The recency window is the cheap mitigation the issue itself recommended first; the
durable queue earns a slot only if 30-day staleness proves insufficient.

### Folded Codex source-handling nits (1 file: `scripts/convert-sources.sh`)
- **#16** — a failed input is archived to gitignored `.raw/` where it is easy to
  forget. Print a summary line naming each archived failure so it stays visible.
- **#17** — a multi-sheet spreadsheet currently keeps only the first sheet's CSV.
  Emit one CSV per sheet.

### Verification
- `lookup-misses.sh` self-check (assert-based): a miss for library A does not
  surface for library B; a miss older than the window is dropped; both go RED if
  the respective filter is removed.
- A real 2-sheet `.xlsx` through `convert-sources.sh` yields two CSVs; a
  deliberately-failing input prints the `.raw/` summary line.

---

## #70 — Library-knowledge discovery: one-line `/start` pointer (stateless git probe)

### Pain
The only way to find a newly-filed article is to already suspect it exists and run
`/stacks:lookup`. Discovery is pull-only, so curated, audited knowledge accumulates
in the library while consuming repos keep solving problems the library already
answers. Since most stack work happens in the field (a consuming repo, not the
library itself), pushing "what's new" toward those repos is the payoff.

### Design (zero stacks code — entirely a workspace-toolkit `/start` hook)
`/start` (owned by workspace-toolkit / ChuggiesMart) gains a thin "library news"
line. It reads `~/.config/stacks/config.json` → `.library`, then runs one
stateless git probe against the library repo:

```bash
git -C "$LIBRARY" log --since=7.days --diff-filter=A --name-only -- '*/articles/*.md'
```

Count distinct added article files, collect their parent stack directories, and
show one line when the count is non-zero:

> `📚 Library: 3 new articles in the last 7 days (stacks: mep, llm) — /stacks:lookup to explore.`

Suppressed when the count is 0, or when there is no config / the library path is
unreadable (silent degrade, never an error — matches `/start`'s no-git handling).

**Stateless by design:** a rolling 7-day window, no per-repo subscription list, no
last-seen cursor, no "librarian's choice" curation flag. Discovery is a nudge, not
a curated feed. Those richer pieces (per-stack subscription, two-bucket digest,
curation marker) are explicitly deferred until the nudge proves too blunt.

**Rejected alternative:** stacks emits a `dev/digest/latest.json` on catalog/enrich
and `/start` reads it. It survives shallow clones / rewritten history that a
git-log probe cannot see, but needs emit-side code in two pipelines plus a reader
for identical one-line output. Not worth it now.

### Cross-repo resolution
The fix lives in **workspace-toolkit** (`/start`), not stacks. So:
1. File a workspace-toolkit issue for the `/start` library-news hook (spec = this
   section).
2. Close stacks #70 as "resolved via the workspace-toolkit `/start` hook,"
   pointing at that issue. The capability originated here (config contract,
   article layout) but the implementation is a consumer-side probe.

### Verification (in workspace-toolkit, when built)
- `/start` in a repo whose config points at a library with a recent article add
  shows the line naming the right count and stacks.
- Zero adds, or a missing/unreadable library → no line, no error.

---

## Session integration
- Both plans posted to their GitHub issues (#73, #70).
- #70 spawns a workspace-toolkit issue; #70 in stacks closes pointing there.
- No implementation this session (plan-only, per the session directive).
