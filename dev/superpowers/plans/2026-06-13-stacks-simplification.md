# Plan: stacks simplification (0.21.0)

## Goal (verifiable)

Cut stacks from ~4,650 to ~2,200 source lines by removing machinery that does not
serve the outcome — **drop a source in, ask a question, get a grounded answer** —
while leaving that answer path intact. (Target reflects all decisions resolved:
the three ponytail clean cuts — wave-engine.md, refresh-procedure.md, summary-JSON
envelope — plus the three resolved forks — `shard-batches.sh` and `assert-written.sh`
deleted, `normalize-tags` kept.) Done when: a temp library can `init → new-stack →
catalog → audit → ask` end-to-end on the slimmed pipelines, all bats pass, and no
live (non-archive) file references a deleted symbol.

## Decisions (already made — do not re-litigate)

- **Audit → stateless drift report.** Keep the validator's inline `[DRIFT]/[UNSOURCED]/[STALE]`
  marking. Delete the stateful scaffolding around it: carry-forward, status state machine,
  `reconcile`/`rotate`/`merge` scripts, the convergence pass-loop, schema versioning, the
  extraction-hash skip-list flywheel. Each audit regenerates a fresh "what's drifted/unsourced
  now" report by grepping marks. Research-question generation is dropped with findings-analyst.
- **0.20.0 feature-by-feature:** guide → CUT. comparison → CUT. loop → **KEEP**. inbox quality-gate → CUT (keep routing).
- **Conditional usage cuts (none marked as used → all cut):** extract-reddit → CUT.
  wikilinks + glossary + obsidian → CUT. sharding/wave-caps → FLATTEN to one-agent-unless-large
  (keep the cap, see forks below for how).
- **Consequence:** `synthesizer` agent + `glossary.md`/`invariants.md`/`contradictions.md`
  lose every consumer once wikilinks (only glossary reader) and findings-analyst (only
  contradictions reader) go. invariants had no reader to begin with. So A2 synthesis is cut whole.
- **Second-pass clean cuts (ponytail ultra):** `references/wave-engine.md` → DELETE whole (after
  flatten it just duplicates the two SKILL.md flows it tells them to "go read"; a drift surface).
  `references/refresh-procedure.md` → DELETE whole (orphan — no skill/agent reads it; describes the
  gutted audit). catalog `_w1-w2-summary.json` envelope → DELETE (parent writes JSON then reads it
  back in-process; it already holds the counts as shell vars).
- **Three forks RESOLVED (second ponytail pass):**
  (1) **wave-cap/shard → keep the cap, delete `scripts/shard-batches.sh`.** The cap bounds a real
  resource (concurrent subagent spawns); flatten-to-zero is rejected. But the script has zero
  callers after the audit rewrite — catalog W2 already uses an inline array-slice
  (`CONCEPT_SLUGS[@]:i:CAP`) and audit A1 adopts the same. Bound stays, script goes, one idiom.
  (2) **`normalize-tags` halting gate → KEEP.** Single caller, self-disabling (no-op without
  `allowed_tags` in STACK.md), live downstream consumer (MoC `tags[0]` grouping). Opt-in curation
  at zero default cost; not dead weight.
  (3) **gate-fold → ACCEPT, delete `scripts/assert-written.sh`.** Its only caller is
  `gate-batch.sh`, which already has a write-only mode (`-` structure kind). Inline the mtime+size
  check into gate-batch's loop. 3 gate files → 2.

## Files deleted (16)

```
skills/guide/                       skills/extract-reddit/
agents/comparison-synthesizer.md    agents/findings-analyst.md    agents/synthesizer.md
scripts/reconcile-findings.py       scripts/rotate-findings.sh    scripts/merge-findings.py
scripts/compute-extraction-hash.sh  scripts/wikilink-pass.sh      scripts/extract-reddit-thread.py
scripts/shard-batches.sh            scripts/assert-written.sh
references/obsidian.md               references/wave-engine.md      references/refresh-procedure.md
```

## Records left untouched (dated snapshots, not drift)

`dev/feature-dev/*`, `dev/superpowers/plans/*` (including this file's siblings),
`dev/briefs/*`, `docs/blog-notes/*`, `.claude/memory-bank/archive/*`,
`.claude/memory-bank/active-context-S13-3900x.md`, and existing CHANGELOG entries.
The S14 handoff is written fresh at `/stop`.

---

## Phase 1 — Revert isolated 0.20.0 features (guide, comparison, inbox gate)

Self-contained; leaves a working tree.

1. **guide:** `git rm -r skills/guide/`. In `skills/ask/SKILL.md` delete Step 1.5 (the
   guide-first check) and renumber nothing else (steps are named, not strictly sequential —
   verify the QUERY_SLUG block is fully removed).
2. **comparison:** `git rm agents/comparison-synthesizer.md`. In `skills/catalog-sources/SKILL.md`
   delete Step 5.5 (W0c pre-filter) entirely and the W3 note that points at it. In
   `scripts/regenerate-moc.sh` delete the `comparison_pages` block (lines ~48-57). In
   `templates/stack/STACK.md` delete the `## Comparison Template` section. In
   `templates/stack/index.md` delete the `## Comparisons` section.
3. **inbox gate:** in `skills/process-inbox/SKILL.md` revert the quality gate — remove the
   gate prose, the RECYCLED list, the recycling-bin mkdir/mv, the 4-case commit logic, and
   the Recycled report section. Restore the pre-gate commit guard (skip when MOVED empty) and
   routing-only flow. Keep everything else.

**Verify:** `bash -n` clean on regenerate-moc.sh; `bats tests/` green; grep confirms no live
ref to `guide`, `comparison`, `comparison-synthesizer`, `recycling-bin` outside records.
Commit: `refactor: revert guide/comparison/inbox-gate (0.20.0 cut)`.

## Phase 2 — Remove extract-reddit

1. `git rm -r skills/extract-reddit/ scripts/extract-reddit-thread.py`.

**Verify:** grep `reddit` returns only CHANGELOG (record). Commit: `refactor: remove extract-reddit`.

## Phase 3 — Audit → stateless drift report

The big rewrite. audit-stack 487 → ~120 lines.

1. `git rm agents/findings-analyst.md agents/synthesizer.md scripts/reconcile-findings.py
   scripts/rotate-findings.sh scripts/merge-findings.py scripts/shard-batches.sh
   references/refresh-procedure.md`.
   (`refresh-procedure.md` is an orphan — no skill/agent reads it — so it deletes here with zero
   dangling-ref risk. `shard-batches.sh`'s only callers are A1/A2/A3, all removed/rewritten in this
   phase. `wave-engine.md` and `assert-written.sh` wait: catalog still reads wave-engine until
   Phase 4, and assert-written is deleted in step 5 below once gate-batch absorbs it.)
2. **Rewrite `skills/audit-stack/SKILL.md`** to: Step 0 telemetry → Step 1 gate (drop
   `MAX_AUDIT_PASSES` parse) → Step 2 read STACK.md → A1 dispatch validator agent(s) over
   articles (flattened: one agent unless article count exceeds a threshold, e.g. >25, then
   slice inline with the same `${ARTICLES[@]:i:CAP}` idiom catalog W2 uses — NOT shard-batches.sh;
   parent-side gate via `gate-batch.sh ... article-validated`) → bash report: grep
   `[DRIFT]/[UNSOURCED]/[STALE]` marks across `articles/*.md`, write `dev/audit/report.md` (plain
   list: article slug, marked claim line, mark type; plus counts) → commit + report to user. No
   A2/A2b/A3/A4/A5, no pass-loop, no findings.md, no glossary/invariants/contradictions. Drop the
   `WAVE_ENGINE=...` var and the "Read `$WAVE_ENGINE`" instruction (audit:54) — wave-engine.md is
   being deleted; the only gate-contract fact the rewrite needs (write-or-fail mtime+size) now
   lives in gate-batch.sh after step 5.
3. **Edit `agents/validator.md`:** drop any findings.md / wikilink coupling; the contract is
   "read articles + cited sources, strip prior marks, write fresh inline marks, gate." Verify
   it no longer instructs wikilink-stripping awareness (moot now).
4. **Edit `scripts/assert-structure.sh` + `tests/assert-structure.bats`:** remove the
   `glossary-md` / `invariants-md` structure kinds and their tests (no longer produced). Keep
   `article-md`, `concept-batch`, `dedup-md`, `dedup-meta`. NOTE: the `article-md` kind's
   `extraction_hash` assert (line 27) is NOT touched here — it is removed in Phase 4, the same
   phase that strips the field, so each phase leaves a working tree.
5. **Gate-fold: `git rm scripts/assert-written.sh` after inlining it into `gate-batch.sh`.**
   `assert-written`'s only caller is `gate-batch.sh:38`. Replace that call with the inline
   mtime+size check (`[[ -s "$path" ]]` AND `stat -c %Y "$path"` strictly `>` `$DISPATCH_EPOCH`,
   emitting the same `AGENT_WRITE_FAILURE` label on failure). gate-batch keeps its `-` write-only
   mode, so the standalone use case is preserved. Both pipelines gate through gate-batch only.
6. **`references/wave-engine.md`:** not edited — deleted whole in Phase 4 (after catalog drops
   its reader). The gate-contract essentials each skill needs are inlined into the skill itself
   during its rewrite, so the standalone reference doc goes to zero.

**Verify:** `bats tests/` green; `bash -n` on assert-structure.sh + gate-batch.sh; smoke audit on
the temp stack from the final phase produces `dev/audit/report.md` with correct mark counts; grep
confirms no live ref to `findings-analyst`, `reconcile`, `rotate`, `merge-findings`,
`shard-batches`, `refresh-procedure`, `pass_counter`, `convergence`,
`MAX_AUDIT_PASSES`, `synthesizer`, `invariants`, `contradictions` outside records. (`wave-engine`
AND `assert-written` greps are deferred to Phase 4 — the `assert-written.sh` *script* is deleted
here once gate-batch absorbs it, but its remaining live *mentions* are in catalog prose
(`catalog-sources` 138/415/437) and `references/wave-engine.md`, both cleaned in Phase 4. Grepping
either term at the end of Phase 3 would trip on those Phase-4-owned references. `shard-batches`
stays in this grep — its only callers were audit A1/A2/A3, all gone with this phase's rewrite, and
catalog never referenced it.) Commit: `refactor: audit-stack → stateless drift report`.

## Phase 4 — Slim catalog-sources

catalog-sources 497 → ~250 lines.

1. `git rm scripts/compute-extraction-hash.sh scripts/wikilink-pass.sh references/wave-engine.md`.
   (`wave-engine.md`'s last reader is catalog, removed in step 2 below — so the file and its
   reference die in the same phase, leaving a working tree.)
2. **Edit `skills/catalog-sources/SKILL.md`:** delete Step 5 (W0b prior-findings/skip-list),
   the extraction-hash injection in W2, and Step 7 (W2b wikilink). Drop the `WAVE_ENGINE=...`
   var and the "Read `$WAVE_ENGINE`" instruction (catalog:135); inline the one gate-contract
   sentence the pipeline needs. **Delete the `_w1-w2-summary.json` envelope** — the two write
   blocks (L250, L401) and the read/gate (L474). The parent already holds the W1/W2 counts as
   shell vars in-process; gate on those directly instead of writing JSON to re-read it one
   process later. Flatten W2: drop the `W2_WAVE_CAP=25` wave loop to a single parallel dispatch
   unless slug count exceeds a threshold. Keep W1 (concept-identifier, 1-per-source parallel),
   W1b dedup (`dedup-extractions.py`, minus hash compute), W2 (article-synthesizer), W3 filing,
   W4 MoC (`regenerate-moc.sh`), tag drift check (`normalize-tags.sh`).
   **Reword the surviving `assert-written` prose** in the kept W3 filing step (currently
   `catalog-sources` L437, "...passed their W2 **assert-written** gates"): change "assert-written
   gates" → "W2 write gates". After the Phase 3 gate-fold there is no `assert-written.sh` script —
   the gate is `gate-batch.sh` — so the bare term is a dangling ref to a deleted symbol, which the
   Goal's done-criterion forbids. (The other two catalog mentions, L138 and L415, are removed with
   the `WAVE_ENGINE` instruction and the Step 7 wikilink block deleted above; no separate edit.)
3. **Edit `agents/concept-identifier.md`:** remove skip-list input and `extraction_hash`
   output. Keep slug-immutability check.
4. **Edit `agents/article-synthesizer.md`:** remove `extraction_hash` copy instruction and the
   wikilink note. Keep `last_verified`/`updated`/`sources`/`title`/`tags` frontmatter.
5. **Edit `scripts/assert-structure.sh`:** delete line 27 (the `extraction_hash` assert in the
   `article-md` kind: `grep -qE '^extraction_hash:' ... || fail`). **Load-bearing:** the W2
   catalog gate (`catalog-sources` L377 → `gate-batch.sh ... article-md`) runs this on every
   article; once the field is gone, leaving the assert fails W2 with "missing extraction_hash
   field". `dedup-extractions.py` needs no edit — it computes no hash (the hash is injected at
   `catalog-sources` L326 via `compute-extraction-hash.sh`, removed in step 2). Keep
   `dedup-extractions.py` slug-collision dedup + `source_paths[]` merge as-is.
6. **Edit `skills/ask/SKILL.md`:** remove the `extraction_hash: ""` field from the Karpathy-loop
   new-article frontmatter template (Step 7, line ~191) AND the wikilink instruction at line ~186
   ("Do not write `[[wikilinks]]` — the next `/stacks:audit-stack` wikilink pass handles those")
   — there is no wikilink pass after the cut. Leave line ~170 ("comparison or decision table")
   alone; it is generic prose, not the deleted comparison feature.

**Verify:** smoke catalog on temp stack produces articles with clean frontmatter (no
extraction_hash); grep confirms no live ref to `extraction_hash`, `compute-extraction`,
`wikilink`, `wave-engine`, `assert-written`, `W0b`, `skip.list`, `summary.json` outside records.
(`assert-written` is grepped HERE, not Phase 3 — this is the phase that removes its last live
mentions: wave-engine.md is deleted in step 1, catalog 138/415 with their blocks in step 2, and 437
is reworded in step 2.) Commit: `refactor: slim catalog-sources`.

## Phase 5 — References, templates, README

1. **`references/`:** nothing to do — `obsidian.md` (Phase 1-adjacent), `refresh-procedure.md`
   (Phase 3), and `wave-engine.md` (Phase 4) are all deleted. Only `default-topic-template.md`
   survives; leave it.
2. **`templates/stack/STACK.md`:** remove `MAX_AUDIT_PASSES`/`ROTATION_CYCLES` knobs (if
   present), any `extraction_hash` frontmatter field, synthesizer mention. Keep scope, source
   hierarchy, topic template, filing rules, tag vocabulary.
3. **`templates/library/CLAUDE.md`, `templates/library/.gitignore`:** drop guide mention;
   drop `.obsidian/` ignore line.
4. **`README.md`:** rewrite the command list and architecture sections to the surviving set
   (init-library, new-stack, catalog-sources, ask, process-inbox, audit-stack, loop). Remove
   guide/comparison/extract-reddit/findings-flywheel/wikilink/obsidian prose.

**Verify:** grep `obsidian`, `wikilink`, `guide`, `findings` across `references/ templates/
README.md` returns nothing. Commit: `docs: align references/templates/README to slimmed system`.

## Phase 6 — Version, CHANGELOG, doc scrub, issue reconciliation

1. **Bump 0.21.0** via `jq` in both `.claude-plugin/plugin.json` and
   `.claude-plugin/marketplace.json`. (Breaking: skills removed, audit findings schema dropped.)
2. **CHANGELOG.md:** prepend `## 0.21.0 — 2026-06-13` with ELI8 headline + what was removed
   and why (simplification to the answer path). Note `#7`/`#18`/`#40` reverted, `#14` kept.
3. **CLAUDE.md (this repo):** scrub gotchas that reference removed machinery — the `jq -e`
   findings-gate gotcha, the orchestrator-dispatch gotchas (if no longer applicable), any
   glossary/W0b mention. Keep gotchas still true (template .gitignore self-shadow, sub-agent
   text-not-exit-code).
4. **Live memory-bank:** rewrite `.claude/memory-bank/system-patterns.md`,
   `tech-context.md`, `project-brief.md` to describe the slimmed two-pipeline system (drop
   audit flywheel, 6-agent roster → 3 agents, extraction-hash, wikilink, perl dep if now
   unused). Regenerate `start-brief.md` via `/workspace-toolkit:refresh-start-brief` (or let
   it self-heal at next `/start`).
5. **Issues:** close `#52` (wikilink-pass corruption) as resolved-by-deletion. Note
   `#7`/`#18`/`#40` reverted (comment, do not reopen — reopening implies rebuild). Check
   `#10`/`#51` still relevant.

**Verify:** `jq -e '.version=="0.21.0"'` on both files; versions match; full `bats tests/`
green; final end-to-end smoke (below) passes. Commit: `chore: bump 0.21.0, scrub docs (#7 #18 #40 reverted, #52 closed)`. Push.

---

## End-to-end smoke (the real "does it work" gate — run in Phase 6)

```bash
bash scripts/install.sh
# restart claude code, then in ~/tmp/test-lib:
/stacks:init-library ~/tmp/test-lib
/stacks:new-stack test
# drop 2-3 small .md sources into test/sources/incoming/
/stacks:catalog-sources test     # → articles/, index.md, no extraction_hash, no wikilinks
/stacks:audit-stack test         # → dev/audit/report.md with drift/unsourced counts
/stacks:ask "<question about the sources>"   # → grounded answer, cites articles
rm -rf ~/tmp/test-lib
```

Pass = articles written with clean frontmatter, audit report lists marks, ask returns a
cited answer. Fail anywhere = the slim broke the answer path; fix before push.

## Risk notes

- Low logic risk (mostly deletion + prose simplification). The one trap is a **dangling
  reference to a deleted script/wave** left in a rewritten skill — the per-phase grep gate
  catches it. Re-grep the cut-term list after each phase against live dirs only.
- Insurance scripts that STAY: `normalize-tags.sh` (self-disabling, live MoC consumer),
  `assert-structure.sh`, `gate-batch.sh` (now absorbs `assert-written`'s mtime+size check),
  `collision-dest.sh`, `dedup-extractions.py`. Deleted from this set: `assert-written.sh` (folded
  into gate-batch) and `shard-batches.sh` (replaced by inline `[@]:i:CAP` slicing in both
  pipelines). The gate itself is never cut — it's the ponytail-minimum self-check.
- If a temp-stack smoke can't run headless this session, the bats + `bash -n` + grep gates are
  the floor; flag the deferred manual smoke explicitly rather than claiming verified.
