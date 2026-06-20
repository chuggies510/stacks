# enrich-stack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/stacks:enrich-stack {stack}` + an `enrichment` agent that acquire grounding sources for audit soft spots, plus the audit/validator contract fix that makes the soft-spot list machine-readable.

**Architecture:** Mirrors the `audit-stack`→`validator` split. The `enrichment` agent does per-gap web acquisition (search→fetch→verify→tier→dedup) and writes a findings file; the `enrich-stack` skill owns batching, the gate, URL-dedup, the operator-approval gate, and all repo writes. The audit pipeline is changed to emit a durable `dev/audit/soft-spots.tsv` (verbatim claim, structured) that enrich consumes instead of parsing `report.md` markdown.

**Tech Stack:** Claude Code plugin (markdown agents + skills, bash, bats). Design detail: `dev/superpowers/specs/2026-06-19-enrich-stack-design.md`.

**User decisions (already made):**
- "Fix the contract (3 files)" — change validator + audit-stack to emit machine-readable `soft-spots.tsv`; enrich reads the TSV. (chosen over enrich-only markdown parsing)
- "Agent + enrich-stack skill" — build both, end-to-end runnable. (chosen over agent-only)
- Codex review punch list folded in; content-aware internal dedup and multi-candidate rows rejected (YAGNI).
- User delegated overnight execution ("you got this, use codex for review when ready") — execution handoff AskUserQuestion is skipped; coordinator implements directly, codex reviews, verified work is committed + pushed.

**Run constraint:** `gate-batch.sh` uses GNU `stat -c %Y`; the catalog/audit/enrich pipeline runs on the Linux boxes (Pi 192.168.3.4 / desktop 192.168.3.11), not macOS. Pre-existing; not fixed here.

---

## File map

| File | Change | Task |
|------|--------|------|
| `agents/validator.md` | SOFTSPOT output → 4-field `SOFTSPOT⇥slug⇥claim⇥reason`, claim verbatim | 1 |
| `skills/audit-stack/SKILL.md` | persist `dev/audit/soft-spots.tsv`; render report soft-spots from 4 fields; commit the tsv | 1 |
| `scripts/assert-structure.sh` | add `enrichment-findings` shape case | 2 |
| `tests/assert-structure.bats` | tests for the new shape | 2 |
| `agents/enrichment.md` | new per-gap acquisition agent | 3 |
| `skills/enrich-stack/SKILL.md` | new orchestrator skill | 4 |
| `.claude-plugin/plugin.json`, `marketplace.json`, `CHANGELOG.md` | 0.28.0 → 0.29.0 + entry | 5 |

---

## Task 1: Soft-spot contract — machine-readable `soft-spots.tsv`

**Goal:** `validator` emits the verbatim claim and reason as separate tab fields; `audit-stack` persists the aggregated soft spots as `dev/audit/soft-spots.tsv` (the enrich input) and still renders `report.md`.

**Files:**
- Modify: `agents/validator.md` (Output section + Example 3 + the soft-spot prose)
- Modify: `skills/audit-stack/SKILL.md` (Step 4 aggregation + Step 5 commit)

**Acceptance Criteria:**
- [ ] validator SOFTSPOT line format is `SOFTSPOT⇥slug⇥claim⇥reason`; `claim` is the complete verbatim article sentence (tabs/newlines collapsed). CORRECTION unchanged.
- [ ] audit-stack writes `$STACK/dev/audit/soft-spots.tsv` with `slug⇥claim⇥reason` rows (empty file if zero soft spots).
- [ ] `report.md` soft-spot bullets render `` - `slug` — "claim" — reason `` from the 4 fields.
- [ ] Step 5 `git add` includes `soft-spots.tsv`.

**Verify:** fixture aggregation test (below) → `soft-spots.tsv` has exactly the seeded rows; report renders the joined bullet.

**Steps:**

- [ ] **Step 1: validator Output contract.** In `agents/validator.md`, change the SOFTSPOT spec and example. The Output block (currently `KIND<TAB>slug<TAB>description`) becomes: CORRECTION stays `CORRECTION<TAB>slug<TAB>description`; SOFTSPOT becomes `SOFTSPOT<TAB>slug<TAB>claim<TAB>reason` where `claim` is the **complete verbatim sentence** from the article body (collapse internal tabs/newlines to spaces) and `reason` is the one-line why-it's-soft. Update the prose in step 3's "No cited source" bullet and the Output section accordingly. Replace Example 3's record:

  ```
  SOFTSPOT	cooling-tower-cycles	Cycles of concentration above 7 are rarely achievable in practice.	no scoped source covers practical cycle limits
  ```

- [ ] **Step 2: audit-stack Step 4 aggregation.** In `skills/audit-stack/SKILL.md` Step 4, keep `emit()` for CORRECTION only. Render soft spots from 4 fields and write the tsv. Replace the soft-spot render + add the tsv write:

  ```bash
  # soft spots: render from 4-field SOFTSPOT lines (slug, claim, reason)
  if [[ "$N_SOFT" -gt 0 ]]; then
    printf '%s\n' "$AUDIT_LINES" | awk -F'\t' '$1=="SOFTSPOT"{printf "- `%s` — \"%s\" — %s\n", $2, $3, $4}'
  else echo "_None. Every claim ties to a cited source._"; fi
  ```

  After the report block, before `rm -f "$STACK"/dev/audit/_audit-*.md`, write the durable tsv:

  ```bash
  # Durable machine-readable soft-spot list — the /stacks:enrich-stack input.
  # slug<TAB>claim<TAB>reason. Written even when empty so enrich-stack can tell
  # "audited, none soft" from "never audited".
  printf '%s\n' "$AUDIT_LINES" \
    | awk -F'\t' '$1=="SOFTSPOT"{print $2"\t"$3"\t"$4}' \
    > "$STACK/dev/audit/soft-spots.tsv"
  echo "Wrote $STACK/dev/audit/soft-spots.tsv ($N_SOFT soft spots)"
  ```

- [ ] **Step 3: audit-stack Step 5 commit.** Add the tsv to the `git add` line:

  ```bash
  git add "$STACK/articles/" "$STACK/dev/audit/report.md" "$STACK/dev/audit/soft-spots.tsv" "$STACK/log.md"
  ```

- [ ] **Step 4: Verify the aggregation with a fixture (deterministic, no agent dispatch).**

  ```bash
  cd /Users/chris/chungus/dev/library-stack
  T=$(mktemp -d); mkdir -p "$T/dev/audit"
  printf 'CORRECTION\tvav-min\t"30%%" → "20%%" per [src]\n' >  "$T/dev/audit/_audit-0.md"
  printf 'SOFTSPOT\tcooling-cycles\tCycles above 7 are rarely achievable.\tno cited source\n' >> "$T/dev/audit/_audit-0.md"
  AUDIT_LINES=$(cat "$T"/dev/audit/_audit-*.md)
  printf '%s\n' "$AUDIT_LINES" | awk -F'\t' '$1=="SOFTSPOT"{print $2"\t"$3"\t"$4}' > "$T/dev/audit/soft-spots.tsv"
  cat "$T/dev/audit/soft-spots.tsv"   # expect: cooling-cycles<TAB>Cycles above 7 are rarely achievable.<TAB>no cited source
  printf '%s\n' "$AUDIT_LINES" | awk -F'\t' '$1=="SOFTSPOT"{printf "- `%s` — \"%s\" — %s\n", $2, $3, $4}'
  # expect: - `cooling-cycles` — "Cycles above 7 are rarely achievable." — no cited source
  rm -rf "$T"
  ```

- [ ] **Step 5: Commit.**

  ```bash
  git -C /Users/chris/chungus/dev/stacks add agents/validator.md skills/audit-stack/SKILL.md
  git -C /Users/chris/chungus/dev/stacks commit -m "feat(audit): emit machine-readable soft-spots.tsv (4-field verbatim claim)"
  ```

---

## Task 2: `enrichment-findings` gate shape + bats

**Goal:** `assert-structure.sh` validates an enrichment findings file (every line a `CANDIDATE|WEAK|DUP|NOSOURCE` tab record); bats covers valid + malformed + empty.

**Files:**
- Modify: `scripts/assert-structure.sh` (new `case`)
- Modify: `tests/assert-structure.bats` (new block)

**Acceptance Criteria:**
- [ ] `assert-structure.sh f enrichment-findings label` exits 0 on a valid findings file, 1 on a malformed line or no valid rows.
- [ ] `bats tests/assert-structure.bats` passes.

**Verify:** `bats /Users/chris/chungus/dev/stacks/tests/assert-structure.bats` → all tests pass.

**Steps:**

- [ ] **Step 1: Add the bats block (red first).** Append to `tests/assert-structure.bats`:

  ```bash
  # ── enrichment-findings ────────────────────────────────────────────────────────

  @test "enrichment-findings: valid file passes" {
    local f="$TEST_TMP/enrich.md"
    printf 'CANDIDATE\tgap-0\tprompt-engineering\t\thttps://x/y\t1\tTitle\tquote\n' >  "$f"
    printf 'NOSOURCE\tgap-1\tcontext-mgmt\t\t\t\t\tno source found\n'              >> "$f"
    run_script "$f" enrichment-findings
    [ "$status" -eq 0 ]
  }

  @test "enrichment-findings: malformed line fails" {
    local f="$TEST_TMP/enrich.md"
    printf 'CANDIDATE\tgap-0\tslug\t\turl\t1\tTitle\tquote\n' >  "$f"
    printf 'garbage line with no kind\n'                      >> "$f"
    run_script "$f" enrichment-findings
    [ "$status" -eq 1 ]
    [[ "$output" == *"STRUCTURE_FAILURE"* ]]
  }

  @test "enrichment-findings: empty file fails" {
    local f="$TEST_TMP/enrich.md"
    : > "$f"
    run_script "$f" enrichment-findings
    [ "$status" -eq 1 ]
    [[ "$output" == *"STRUCTURE_FAILURE"* ]]
  }
  ```

- [ ] **Step 2: Add the case (green).** In `scripts/assert-structure.sh`, before the `*)` default:

  ```bash
  enrichment-findings)
    grep -qE '^(CANDIDATE|WEAK|DUP|NOSOURCE)'$'\t' "$path" \
      || fail "no enrichment findings rows (CANDIDATE/WEAK/DUP/NOSOURCE)"
    if awk 'NF && $0 !~ /^(CANDIDATE|WEAK|DUP|NOSOURCE)\t/ {bad=1} END{exit bad?1:0}' "$path"; then :; else
      fail "malformed enrichment findings line (not KIND<TAB>...)"
    fi
    ;;
  ```

- [ ] **Step 3: Run bats.** `bats /Users/chris/chungus/dev/stacks/tests/assert-structure.bats` → all green (existing + 3 new).

- [ ] **Step 4: Commit.** `git -C .../stacks add scripts/assert-structure.sh tests/assert-structure.bats && git commit -m "feat(gate): enrichment-findings shape + tests"`

---

## Task 3: `enrichment` agent

**Goal:** New `agents/enrichment.md` — per-gap web acquisition with four verdicts, writing the findings TSV that Task 2's shape validates and Task 4's skill parses.

**Files:**
- Create: `agents/enrichment.md`

**Acceptance Criteria:**
- [ ] Frontmatter: `tools: Glob, Grep, Read, Write, WebSearch, WebFetch`, `model: sonnet`, description names "does not stage or catalog".
- [ ] Sections: intro + Why, Judgment Bias, Input, Process (verdict table), Output (TSV `KIND⇥gap_id⇥slug⇥source_ref⇥url⇥tier⇥title⇥quote`), 3 examples (CANDIDATE, DUP, NOSOURCE).
- [ ] Output format exactly matches the `enrichment-findings` shape and the skill's parser.

**Verify:** structural grep (frontmatter + 4 verdicts + 8-field output line) + the live smoke-test in Task 4 Step 6.

**Steps:**

- [ ] **Step 1: Write `agents/enrichment.md`** with the full content from the spec's "The `enrichment` agent" section: intro/Why, Judgment Bias (verify the claim not the topic; default NOSOURCE/WEAK when unsure; never fabricate), Input (gap rows `gap_id⇥slug⇥claim⇥reason`, STACK.md tiers+scope, filed-sources listing `slug⇥url`, `$STACK`/`$BATCH_TAG`), Process (query→WebSearch→WebFetch→verify-by-falsification→tier→URL-dedup) with the four-verdict table, Output (`dev/enrich/_enrich-${BATCH_TAG}.md`, one 8-field tab row per gap, fields tab/newline-stripped), and three worked examples. (Authored verbatim in this session — see committed file.)

- [ ] **Step 2: Structural check.**

  ```bash
  A=/Users/chris/chungus/dev/stacks/agents/enrichment.md
  grep -qE '^tools: .*WebSearch.*WebFetch' "$A" && grep -qE '^model: sonnet' "$A" && echo OK-frontmatter
  for v in CANDIDATE WEAK DUP NOSOURCE; do grep -q "$v" "$A" || echo "MISSING $v"; done
  ```

- [ ] **Step 3: Commit.** `git -C .../stacks add agents/enrichment.md && git commit -m "feat(agent): enrichment — per-gap source acquisition for audit soft spots"`

---

## Task 4: `enrich-stack` skill

**Goal:** New `skills/enrich-stack/SKILL.md` — gate → stale-check → batch+dispatch → aggregate+URL-dedup → operator approval → stage-with-reverify → report.

**Files:**
- Create: `skills/enrich-stack/SKILL.md`

**Acceptance Criteria:**
- [ ] Gate requires `catalog.md`, STACK arg, STACK.md, and a non-empty `dev/audit/soft-spots.tsv` (else "run audit-stack first" / "nothing to enrich").
- [ ] Stale-check drops gaps whose verbatim claim is no longer in the article (`grep -Fq`); assigns `gap-N` ids.
- [ ] Dispatch CAP=12, parallel, `subagent_type stacks:enrichment`, gated by `gate-batch.sh ... enrichment-findings`.
- [ ] Aggregates across batches, dedups by URL, presents an approval table, stages only approved CANDIDATE/WEAK into `sources/incoming/` with the bold-field header, re-verifies the quote after re-fetch.
- [ ] No auto-catalog, no commit; reports DUP manual actions + NOSOURCE list + next step.

**Verify:** (a) gate+parse+stale-check fixture run (below) on real llm articles; (b) live single-gap agent smoke-test in Step 6.

**Steps:**

- [ ] **Step 1: Write `skills/enrich-stack/SKILL.md`** — full content from the spec's "The `enrich-stack` skill" section (Steps 0-8), using the house idioms: `STACKS_ROOT="$CLAUDE_PLUGIN_ROOT"` telemetry, the catalog.md/STACK/STACK.md/soft-spots.tsv gate, the stale-check loop writing `dev/enrich/_gaps.tsv` (`gap-N⇥slug⇥claim⇥reason`), the filed-sources listing (`slug⇥url` from `**Source:**` lines, excluding `incoming/ trash/ .raw/`), CAP=12 slice + parallel `Agent` dispatch + `gate-batch.sh "$EPOCH" enrichment enrichment-findings "${BATCHFILES[@]}"`, aggregate+URL-dedup, the approval gate (present table; nothing written until confirmed; default = stage CANDIDATEs, WEAK opt-in, never DUP/NOSOURCE; cancel cleans `_enrich-*.md`), staging with the bold-field header + `collision-dest.sh` + post-fetch quote re-verify, and the report (DUP `slug → source_ref → quote`, NOSOURCE list, "run /stacks:catalog-sources then re-audit"; no commit). (Authored verbatim in this session — see committed file.)

- [ ] **Step 2: Verify gate + stale-check against real articles (deterministic).**

  ```bash
  cd /Users/chris/chungus/dev/library-stack
  # seed a soft-spots.tsv: one claim that IS in an article, one that is not
  REAL=$(grep -rl . llm/articles/prompt-engineering.md >/dev/null 2>&1 && echo llm/articles/prompt-engineering.md)
  CLAIM=$(awk 'NF>8 && /\./{print; exit}' llm/articles/prompt-engineering.md | sed 's/\t/ /g')
  T=llm/dev/audit/soft-spots.tsv.test
  printf 'prompt-engineering\t%s\tseeded real claim\n' "$CLAIM" >  "$T"
  printf 'prompt-engineering\tThis sentence is not in the article at all zzz.\tseeded fake\n' >> "$T"
  # run the stale-check loop body against $T → expect 1 kept (gap-0), 1 stale
  i=0; STALE=0
  while IFS=$'\t' read -r slug claim reason; do
    art="llm/articles/$slug.md"
    if [[ ! -f "$art" ]] || ! grep -Fq "$claim" "$art"; then STALE=$((STALE+1)); continue; fi
    echo "KEEP gap-$i $slug"; i=$((i+1))
  done < "$T"
  echo "kept=$i stale=$STALE"   # expect kept=1 stale=1
  rm -f "$T"
  ```

- [ ] **Step 3: Commit.** `git -C .../stacks add skills/enrich-stack/SKILL.md && git commit -m "feat(skill): enrich-stack — acquire sources for audit soft spots (#64)"`

---

## Task 5: Version bump + CHANGELOG

**Goal:** Plugin 0.28.0 → 0.29.0 (new skill + agent), `plugin.json`/`marketplace.json` synced, one CHANGELOG entry.

**Files:**
- Modify: `.claude-plugin/plugin.json`, `marketplace.json`, `CHANGELOG.md`

**Acceptance Criteria:**
- [ ] `jq -r .version .claude-plugin/plugin.json` == `0.29.0`; marketplace.json version matches.
- [ ] CHANGELOG has a `## 0.29.0 — 2026-06-19` entry: bold ELI8 headline + one bullet per change.

**Verify:** `jq` version equality both files; `head CHANGELOG.md` shows the entry.

**Steps:**

- [ ] **Step 1: Bump versions with jq (never Edit on JSON).**

  ```bash
  cd /Users/chris/chungus/dev/stacks
  tmp=$(mktemp); jq '.version="0.29.0"' .claude-plugin/plugin.json > "$tmp" && mv "$tmp" .claude-plugin/plugin.json
  # marketplace.json: find the stacks entry's version key and set it
  tmp=$(mktemp); jq '(.. | objects | select(.name?=="stacks") | .version) = "0.29.0"' marketplace.json > "$tmp" && mv "$tmp" marketplace.json
  jq -r '.version' .claude-plugin/plugin.json
  ```

- [ ] **Step 2: CHANGELOG entry** (prepend, body-file style — backtick-safe):

  ```markdown
  ## 0.29.0 — 2026-06-19

  **The pipeline can now go *find* sources, not just ingest what you drop in.** `/stacks:audit-stack` flags soft spots (article claims with no cited source); closing them used to be all-manual web-searching. The new `/stacks:enrich-stack {stack}` acquires candidate sources for you.
  - New `enrichment` agent: per soft spot, web-searches for one grounding source, verifies it states the actual claim (not just the topic), rates its tier, and dedups against already-filed sources. Four verdicts: CANDIDATE / WEAK (low-tier only) / DUP (already filed) / NOSOURCE. (`agents/enrichment.md`)
  - New `/stacks:enrich-stack` skill: reads the audit's soft spots, drops stale ones, dispatches the agent in batches, then presents found sources for approval and stages only what you approve into `incoming/` — never auto-ingests. (`skills/enrich-stack/SKILL.md`)
  - `audit-stack` now persists a machine-readable `dev/audit/soft-spots.tsv` (verbatim claim + reason) so enrich reads structured data, not the human report's markdown. validator emits the claim and reason as separate fields. (`agents/validator.md`, `skills/audit-stack/SKILL.md`)
  - New `enrichment-findings` gate shape + bats coverage. (`scripts/assert-structure.sh`, `tests/assert-structure.bats`)
  ```

- [ ] **Step 3: Commit.** `git add -A && git commit -m "release: 0.29.0 — enrich-stack + enrichment agent (#64)"`

---

## Self-review

- **Spec coverage:** contract fix (T1) ✓, gate shape (T2) ✓, agent (T3) ✓, skill all 8 steps (T4) ✓, version (T5) ✓. Rejected items stay rejected.
- **Type consistency:** findings TSV `KIND⇥gap_id⇥slug⇥source_ref⇥url⇥tier⇥title⇥quote` is identical in agent Output (T3), assert-structure shape (T2), and skill parser (T4). soft-spots.tsv `slug⇥claim⇥reason` identical in audit-stack write (T1) and skill read (T4). `_gaps.tsv` `gap-N⇥slug⇥claim⇥reason` identical in skill stale-check (T4) and agent Input (T3).
- **No placeholders:** agent/skill bodies are authored verbatim into the files this session (the plan points at the spec for the long-form content rather than duplicating 200 lines twice; the committed files are the source of truth).

## Verification summary (what runs overnight vs. what waits for the operator)

- **Automated/deterministic (run now):** bats (T2), fixture aggregation (T1 Step 4), fixture gate+stale-check on real articles (T4 Step 2), jq version equality (T5).
- **Live, low-risk (run now):** one `enrichment` agent smoke-test on a single real llm soft spot → confirm the findings file passes `enrichment-findings`.
- **Operator-gated (morning):** full `/stacks:enrich-stack llm` — has an approval gate and stages web content; not run unattended. Requires regenerating `soft-spots.tsv` via a fresh `audit-stack llm` first.
