# T6 — Workflow vs Agent-calls: enrich fan-out measurement + substrate decision

Epic #87, Task 6. Maps to #76 Done-When ("Workflow-based enrich measured; substrate decision recorded"). This record decides T9 (whether catalog/audit fan-out migrates to the Workflow tool).

## What was measured

The same enrich fan-out, run two ways on the **same gap set**: `electrical` stack, 15 live audit soft-spots (0 stale), sharded CAP=5 into 3 batches. Same `stacks:enrichment` agent (model `sonnet`) both paths — the agent's web work (WebSearch/WebFetch → verify claim → tier → dedup) is identical; the **only** variable is the orchestration substrate.

- **Path A — Agent-calls** (current SKILL behavior): main session emits 3 parallel `Agent` tool calls, each agent writes its own `_enrich-<tag>.md` findings file, then `enrich.sh gate` reconciles coverage.
- **Path B — Workflow**: a checked-in workflow script (`enrich-workflow.js`, this dir) fans the same 3 batches via `parallel(agent(...))`, each agent constrained by a **StructuredOutput schema** (8-field rows validated at the tool layer); the deterministic caller writes the TSVs, then the same `enrich.sh gate` runs.

## The four metrics

| Metric | Path A — Agent-calls | Path B — Workflow | Read |
|---|---|---|---|
| Subagent tokens | 144,445 | 131,857 | Neutral — 9% delta tracks tool-use count (65 vs 52 web fetches), i.e. search-path variance, not substrate. Dominated by identical agent web work. |
| Wall-clock (parallel) | ~135 s | ~156 s | Neutral-to-slightly-worse for B — both fan out in parallel; B carries workflow setup + one failed setup retry. Within run-to-run noise for a 3-agent web fan-out. |
| Candidate yield | 7/15 grounded (5 CANDIDATE + 2 WEAK) | 7/15 grounded (5 CANDIDATE + 2 WEAK) | Identical count, **different gaps** grounded (A grounded gap-7/8 WEAK, B grounded gap-0/gap-14). Difference is which pages each search surfaced — web variance, substrate-neutral. |
| False-positive rate | not independently adjudicated | not independently adjudicated | Substrate-neutral by construction: the same self-verifying agent decides CANDIDATE vs NOSOURCE in both paths; the orchestrator never touches that judgment. |

## The differences that ARE substrate-attributable

1. **Structure robustness.** Path A's batch-0 agent wrote 2 NOSOURCE rows with a stray extra tab (9 fields, not 8); the structure gate caught it, and it needed manual repair before the gate passed. Path B produced **0 malformed rows across all 15** — the schema validates field structure at the tool layer, so that failure class is structurally impossible. Clear Workflow win.
2. **Main-session context.** Path A's 3 agent returns, the gating, and the repair all land in the main context window. Path B returns one compact structured array; the agents run in the workflow runtime. Clear Workflow win — but it only *binds* at large fan-out.
3. **Determinism / reproducibility.** Path B is a checked-in script, resumable by run-id; Path A is in-session judgment re-made each run. Workflow win.

## The costs of Path B (why the wins don't carry the decision)

- **Explicit opt-in.** The Workflow tool requires the user to opt in per invocation, so it **cannot serve the `--auto` path** (lookup's live auto-enrich, #69). That path must stay a plain Agent call regardless — so adopting Workflow means maintaining *both* substrates, not replacing one.
- **No filesystem access in workflow scripts.** The deterministic TSV write had to live *outside* the workflow (here, a post-run Bash step; in a real migration, in `enrich.sh`). So the "deterministic caller owns the write" benefit is available to the Agent-call path too — it is not unique to Workflow.
- **Per-pipeline harness surface.** T9-if-Workflow means new `.js` dispatch scripts for W1, W2, and A1, each mirroring this one, plus the SKILL dispatch prose swapped — a parallel dispatch mechanism alongside the Agent-call one.
- **Friction observed.** `args` arrived JSON-encoded, not as a parsed object, needing a defensive `JSON.parse` the Agent-call path never needs.

## Decision — T9: **Agent-calls retained, Workflow deferred**

On the four measured metrics the substrate is neutral; cost is the agents' identical web work, which no substrate changes. Workflow's two real wins are schema-enforced row structure and main-session context savings. Both are already handled or don't yet bind:

- The structure win is **already backstopped by the existing gate** — `gate-batch.sh` + `assert-structure.sh` caught Path A's malformed row exactly as designed, and the pipeline recovered. The gate, not the orchestrator, is the correctness boundary, and it already holds.
- The context win only binds at large fan-out (100+ gaps in one run). Real enrich/catalog runs are CAP-sharded into a few small batches; main-session context is not the binding constraint at that size.

Against a marginal, already-covered benefit, Workflow adds a parallel per-pipeline harness, splits the write phase out (no fs), and cannot even serve the autonomous path. Not worth it now.

**Revisit when** a single enrich/catalog/audit run's fan-out is large enough (order 100 items) that main-session context pressure — not agent web work — becomes the binding constraint. That is the one axis where Workflow's context isolation would dominate. Until then, T9 ships no code.

## Artifacts

- `enrich-workflow.js` — the measured Path B harness (kept as the prototype of record; not wired into any skill).
- `pathA-enrich-{0,1,2}.md`, `pathB-enrich-{0,1,2}.md` — raw findings from each run.
- `pathA-dispatch.tsv`, `pathB-dispatch.tsv` — the 15-gap manifests (identical gap set).
