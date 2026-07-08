---
session: 19
---

# stacks Active Context

## Current state
- Plugin at 0.49.0. The #77 schema-drift cluster is closed (#88/#89/#90/#92 + tracking parent #77). Tool and corpus now agree on article shape, source-ref form, per-source tier, and gate reconciliation.
- Epic #87 (pipeline orchestration) closed in S18; all three fan-out pipelines run through `scripts/pipeline/{catalog,audit,enrich}.sh`.
- Open issues: 5, all standalone singletons — no epic left in flight. #54 (maintenance skills load in every repo), #70 (repos can't discover new library knowledge), #73 (lookup-miss telemetry can't tell libraries apart), #86 (enrich cold-start an empty stack), #93 (catalog W1 gate rejects a pure-reference source).

## Open thread

None, closed clean. The #77 cluster completed as a full unit: four sub-issues fixed across two repos, verified (dedup bats 6/6, self-checks 18/10/6/20, corpus diff audited line-by-line), a codex review caught one latent gate hole that was fixed, all issues closed, both repos pushed, durable layers reconciled.

## Next priority

User signalled (`/stop`: "keep going on this in next fresh sesh") to continue on stacks next session. No epic remains — pick from the 5 standalones. Highest-leverage candidates: #93 (pure-reference W1 gate, small, blocks cataloging reference-only sources) and #86 (empty-stack cold-start). #70/#73 are the knowledge-discovery pair (could form a small epic if both taken). #54 is a load-scope footgun. No urgent production issue.

---

## CONTEXT HANDOFF - 2026-07-07 (Session 19)

### Session summary

Closed the #77 schema-drift cluster in one session — the follow-on epic S18 flagged as next. Four sub-issues spanning the stacks tool repo and the library corpus it produced: #89 (dedup collapsed per-source tier to one first-seen scalar per slug — now carries a `source_path → tier` map, emits tier inline per source, synthesizer reads it for hierarchy weighting), #90 (dropped the dead `updated` article field, zero readers, stripped from all 1022 corpus articles), #88 (normalized 266 stack-prefixed source-refs to bare form and removed lookup Step 7's dual-resolution fallback), #92 (added `check-coverage.sh --batched` per-batch reconciliation to catch a cross-batch receipt misattribution the global union missed). Work ran as three parallel streams: a sonnet background agent did the mechanical corpus sed migration in the library repo, an opus background agent implemented the #92 gate code, and I did the #89 keystone + doc reconciliation inline — no file overlap by design. A codex review (high effort, danger-full-access sandbox) of the two logic files caught one latent hole — `--batched` silently skipped a manifest batch tag with no supplied receipt-file pair — which was fixed and covered by a new red-when-broken self-check. Closed #77 tracking parent after all four sub-issues verified closed. Reconciled system-patterns.md + tech-context.md to the shipped state (the durable layers had described the tier collapse and #92 gap as still-open).

### Chat

S19-schema-drift-cluster-77

### Changes made

| Change | Status |
|---|---|
| `feat(schema): #77 cluster` — dedup per-source tier, drop `updated`, bare source-refs, per-batch coverage gate (0.49.0) | Committed f8bdf42, pushed |
| `docs(memory-bank): reconcile durable layers to #77 shipped state` | Committed 0911834, pushed |
| Library corpus migration (chuggies510/library-stack): 266 prefix strips + 1022 `updated:` removals | Committed 8526d8f (main), pushed |
| Issues #88/#89/#90/#92 closed via commit keywords; #77 tracking parent closed | Done |

### Knowledge extracted

- `references/article-contract.md` §1/§3/§4 rewritten to the shipped schema (SSOT): `updated` removed, tier-per-source_path semantics + the merged-dedup block format with inline `(tier N)`.
- `system-patterns.md` "Article contract SSOT" + "Output gates" paragraphs and `tech-context.md` check-coverage row reconciled to 0.49.0 (was describing the fixed gaps as open).

### Decisions recorded

- #90: drop `updated` rather than wire a reader (zero readers, `last_verified` already carries provenance, precedent = `extraction_hash`).
- #89 format: tier inline per source `(tier N)`, scalar dropped; only consumer updated is `article-synthesizer` (validator gets tier from STACK.md hierarchy at audit time, never the dedup block).
- #88: left `rewrite-source-refs.sh` untouched (its job is incoming→publisher; new writes are already bare, so extending it to strip prefixes would add dead capability). Prefix-strip done as a one-off migration.

### Next session priority

Continue on stacks (user directive). No epic remains — pull from the 5 standalones: #93 (pure-reference W1 gate) and #86 (empty-stack cold-start) are the small self-contained wins; #70/#73 are a knowledge-discovery pair; #54 a load-scope footgun.

### Open issues

5 open (#54, #70, #73, #86, #93). No stale specs.
