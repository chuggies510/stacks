# Plan — 0.50.0 codex fixes (F1–F4) + #73 minimal gap-queue

Date: 2026-07-07 · Session 20 · Status: plan (not implemented)

Two phases, two releases. Phase 1 fixes the four codex-review findings against the
just-shipped 0.50.0 (re-closes reopened #54 and #93; hardens closed #86). Phase 2
implements the deferred #73 minimal fix per the approved design
(`docs/superpowers/specs/2026-07-07-library-discovery-and-gap-queue-design.md`).
#70 is out of scope here — it is the cross-repo ChuggiesMart#596 `/start` hook.

## Dependency graph

```
Phase 1 (0.50.1, bugfix) — re-close #54, #93
  T1 (F1 assert-structure)      ─┐
  T2 (F2 new-stack persistence) ─┤ independent, different files
  T3 (F4 using-stacks desc)     ─┤
  T4 (F3 enrich scope_topics)   ─┘
        └── CHECKPOINT A: bump 0.50.1, CHANGELOG, commit+push, re-close #54/#93

Phase 2 (0.51.0, minor) — close #73
  T5 (lookup telemetry: +library) ──┐
  T6 (lookup-misses filter + enrich prep passes lib+window)   ← after T4 (same file: enrich.sh) and T5
  T7 (convert-sources #16/#17)  ── independent
        └── CHECKPOINT B: bump 0.51.0, CHANGELOG, commit+push, close #73
```

Only real ordering constraints: **T6 after T4** (both edit `scripts/pipeline/enrich.sh` — serialize to avoid a clobber) and **T6 after T5** (the recency/library filter is only meaningful once lookup records `library`). Everything else is parallelizable.

---

## Phase 1 — Codex fixes (→ 0.50.1)

### T1 · F1: sentinel must be the sole non-blank line (#93)
**File:** `scripts/assert-structure.sh` (the `concept-batch` arm), `tests/assert-structure.bats`
**Change:** replace the whole-file `grep -qE '^# no-concepts:'` accept with: pass if a `^## Concept:` block exists; ELSE pass only if the file's non-blank lines number exactly one AND that line matches `^# no-concepts:[[:space:]]*[^[:space:]]`. Otherwise fail.
**Why:** current check matches the sentinel anywhere, so `prose\n# no-concepts: x` (no concept block) passes W1 → dedup skips it → finish files the source out of `incoming/` = silent data loss.
**Acceptance:**
- Lone `# no-concepts: reason` passes.
- `junk line\n# no-concepts: reason` FAILS.
- Empty file and reason-less `# no-concepts:` still FAIL.
- A real `## Concept:` file still passes; `dedup-md` unaffected (stays strict).
**Verify (red-when-removed):** add bats cases for the junk+sentinel-fails and lone-sentinel-passes; `bats tests/assert-structure.bats` green; reverting the arm turns the junk-fails case red.

### T2 · F2: new-stack survives the per-block shell reset (#54)
**File:** `skills/new-stack/SKILL.md`
**Change:** stop relying on vars set in earlier Bash blocks. Each block references `$CLAUDE_PLUGIN_ROOT` directly (present every block) instead of `$STACKS_ROOT`, and uses the concrete stack name (from `$ARGUMENTS` or the operator's answer) rather than a `$STACK_NAME` shell var carried across blocks. Keep the Step 1 `cd "$LIBRARY"` (cwd DOES persist). Prefer consolidating the deterministic scaffold (resolve + parse + copy template + placeholder-substitute) into a single Bash block so its vars live in one shell; keep the interactive "fill STACK.md now?" as prose after.
**Why:** the harness re-inits the shell per block (env lost, cwd kept); `$STACKS_ROOT`/`$STACK_NAME` are empty in Steps 3/4/6/7, so scaffolding fails from a field repo — #54's goal unmet.
**Acceptance:** running the skill's Bash steps as independent shells (simulating the harness) from a NON-library cwd, with config pointing at a temp library, scaffolds the stack correctly (template copied, placeholders replaced, catalog.md appended, committed).
**Verify (red-when-removed):** a script that executes each ```bash``` block in a fresh `bash -c` (fresh env, shared cwd) against a temp library creates the stack; if any block still reads a non-persisted var, the template copy or catalog append is empty/wrong. Delete the temp library after.

### T3 · F4: correct using-stacks routing prose (#54)
**File:** `skills/using-stacks/SKILL.md` (~lines 26-27, 83-87)
**Change:** rewrite "skills that build or edit the library run from within the library repo" → build skills run from any repo and target the library configured in `~/.config/stacks/config.json` (or cwd if it is itself a library). Fix the "If a build skill can't find catalog.md, you're in..." guidance to match config-resolution.
**Acceptance:** no remaining "from within the library repo" claim for build skills; grep for `from within` / `catalog.md` in the file returns only corrected phrasing.
**Verify:** `grep -nE 'from within|inside the library' skills/using-stacks/SKILL.md` returns nothing stale.

### T4 · F3: scope_topics excludes by heading name, any depth (#86 hardening)
**File:** `scripts/pipeline/enrich.sh` (`scope_topics()` + `--self-check`)
**Change:** end the seedable region only at (a) the next `^## ` heading, or (b) a subsection heading (`^#{3,} `) whose text matches `does not belong` / `excluded` (case-insensitive). Other sub-headers (`### Included`, etc.) stay in-scope and their bullets seed.
**Why:** current logic ends at the FIRST `^### ` (so `### Included` seeds nothing) and misses `^#### ` depth (so `#### does not belong` bullets leak as seeds).
**Acceptance:**
- `## Scope` with `### Included\n- Generics` seeds `Generics`.
- `## Scope\n- A\n#### What does not belong\n- B` seeds only `A`.
- Existing `### What does not belong` exclusion still dropped.
**Verify (red-when-removed):** add both cases to `enrich.sh --self-check`; `bash scripts/pipeline/enrich.sh --self-check` green; reverting the parser turns the `### Included` case red.

### CHECKPOINT A
Bump `plugin.json` + `marketplace.json` to **0.50.1** (jq); CHANGELOG patch entry (bold ELI8 headline + one bullet per finding, plain what+why). Commit `Closes #54, closes #93` (repeat keyword). Push. Verify both issues CLOSED via `gh issue view`. #86 stays closed (hardening rode along — mention it in the entry).

---

## Phase 2 — #73 minimal gap-queue (→ 0.51.0)

### T5 · lookup records the resolved library
**File:** `skills/lookup/SKILL.md` (telemetry call)
**Change:** the skill already resolves `LIBRARY`; add it to the telemetry EXTRA json (`{query, articles, stacks, library}`). No `telemetry.sh` change (it merges EXTRA verbatim).
**Acceptance:** a lookup telemetry record carries `.library` = the absolute library path.
**Verify:** run the lookup telemetry line against a temp `$LOG`; `jq '.library' <last record>` is the resolved path; removing the EXTRA field leaves `.library` null.

### T6 · lookup-misses filters by library + recency; enrich prep passes them
**File:** `scripts/lookup-misses.sh`, `scripts/pipeline/enrich.sh` (prep) — **do T6 after T4** (same enrich.sh)
**Change:** `lookup-misses.sh` gains `select(.library == $lib)` and `select(.ts >= $cutoff)` with a named `WINDOW_DAYS=30` constant (cutoff = now − window; compute the ISO cutoff without `date -d` portability traps — pass it in or use a jq date calc). `enrich.sh prep` passes the resolved library path + window when it mines misses. Records without `.library` fall outside the filter and age out; no migration.
**Acceptance:**
- A miss for library A is NOT surfaced when filtering library B (same stack name).
- A miss older than the window is dropped; one inside is kept.
- No `.library` field → not surfaced under a library filter.
**Verify (red-when-removed):** self-check in `lookup-misses.sh` (or a bats) with a two-library, two-age fixture log; removing either `select` turns the cross-library or stale case red.

### T7 · convert-sources ingest nits (#16, #17)
**File:** `scripts/convert-sources.sh`
**Change:** #16 — after archiving a failed input to gitignored `.raw/`, print a summary line naming each archived failure. #17 — for a multi-sheet spreadsheet, emit one CSV per sheet (not just the first).
**Acceptance:** a deliberately-failing input prints a visible `.raw/` summary naming it; a 2-sheet `.xlsx` yields two CSVs.
**Verify (red-when-removed):** convert a real 2-sheet `.xlsx` → two CSVs (revert → one); convert a failing input → summary line present (revert → silent).

### CHECKPOINT B
Bump to **0.51.0** (minor — new filter behavior + new input handling); CHANGELOG minor entry. Commit `Closes #73`. Push. Verify CLOSED. Update the durable layer at `/stop` with the field-usage model + #73/#70 dispositions.

---

## Notes
- Semver: Phase 1 is a patch (0.50.1 — bugfixes to 0.50.0, no new contract); Phase 2 is minor (0.51.0 — new filter/input behavior). Both bump plugin.json + marketplace.json together.
- Each task carries its own red-when-removed check; no task is "done" until that check passes and goes red on revert.
- #70 is NOT in this plan — it is ChuggiesMart#596 (a workspace-toolkit `/start` hook, zero stacks code).
