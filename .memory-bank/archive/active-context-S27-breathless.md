# Session 27 — breathless — 2026-07-23

## Chat
S27-adopt-memory-v3

## Summary
Single-purpose session: migrated the stacks memory bank from pre-v3 (v2) format
to memory-v3. `/start` flagged two things — the carried S26 handoff was STALE
(recorded v0.66.1 / "validation just closed" while v0.67.0→v0.68.3 and #117/#114/#100
had since shipped with no `/stop` written), and the repo was still PRE_MIGRATION on
memory format. User asked for one mechanical thing: "adopt v3 memory".

Ran `/workspace-toolkit:adopt-memory-v3`. Fleet gate passed (mbp + dev-pi both
V3_OK, 0 in-flight sessions; the only local stacks session was this one — the other
tmux windows were CHUGGIES/monitor/meap2-it, none a pre-v3 stacks session). Ran
`migrate-to-v3.sh`: seeded the live `active-context.md` from the S26 handoff and
archived the v2 predecessor as `active-context-S26-3900x.md`. Then tightened the
three live sections to current reality (the carried handoff predated v0.67-0.68.3 +
the routing-enforcement PRs; freshest live signal is the source→article→lookup
fidelity bug cluster #115/#116/#118/#119) and set frontmatter to session 27 /
breathless. Committed with the fleet marker `[memory-v3-migration]` (65b4cd0),
pushed clean (00c338e..65b4cd0).

Of the 8 commits in the session spine, only 65b4cd0 (the migration) is this
session's work; the other 7 (A/B synthesis self-test v0.67.0→v0.68.3 and routing
enforcement #117/#114/#100, down through 1c133a9) are the un-recorded PRIOR
sessions, not S27.

Closed clean — no open thread, no fork. No new knowledge to route (a chore, not an
ADR): no durable-layer edit, no gotcha, no decision-log entry.

## Notes
FACT: The S26→S27 handoff chain had a gap — v0.67.0→v0.68.3 plus #117/#114/#100
shipped across un-recorded sessions with no `/stop` written, so the S26 live handoff
read stale (v0.66.1 / "validation just closed"). The v3 migration therefore had to
RECONSTRUCT current state from the commit log and issue tracker, not carry it from a
clean handoff. The memory bank's lineage at the v2→v3 boundary is reconstructed, not
carried — a future session auditing provenance should know the seam is here.

FACT: No new capability stood up this session. `~/.config/brave-search.key` exists
but is pre-existing (already noted in the S26 handoff), not acquired now.
