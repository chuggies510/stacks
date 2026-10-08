---
name: catalog-sources
description: Use when new documents must become article-per-concept entries in a knowledge stack, whether already staged or still sitting in some other directory; runs from any repo against the configured library.
---

# Catalog Sources

Process new sources into article-per-concept wiki entries for a knowledge stack.

The deterministic control flow (arg parse, `--from` staging, convert, enum, sharding, dedup, gating, tag-drift, source filing, MoC, cleanup) lives in `scripts/pipeline/catalog.sh` as phase subcommands; state crosses phases through `dev/extractions/{run.env,dispatch-w1.tsv,dispatch-w2.tsv}` files, never shell env. This skill runs the two model dispatches (W1 source-extractor, W2 article-synthesizer) and the interactive near-dup review between the script phases, then does the log+commit.

## Step 0: Telemetry

```bash
STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/settings.json" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | jq -rs '[.[] | (.extraKnownMarketplaces.stacks.source.path)?, (.plugins["stacks@stacks"][0].installPath)?] | map(strings) | .[0] // empty' 2>/dev/null || true)}}"
[ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
[ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
[ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
SKILL_NAME="stacks:catalog-sources" bash "$STACKS_ROOT/scripts/telemetry.sh" 2>/dev/null || true
```

## Step 1: Pick the stack(s)

Two modes, keyed on `$ARGUMENTS`:

- **A stack name is given** (with or without `--from {path}`): catalog that one stack. `--from` stages source files from an existing directory into the stack's `incoming/` before cataloging.
- **No argument**: catalog every stack that has queued sources in `incoming/`, largest batch first. Get the queue:

  ```bash
  STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/settings.json" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | jq -rs '[.[] | (.extraKnownMarketplaces.stacks.source.path)?, (.plugins["stacks@stacks"][0].installPath)?] | map(strings) | .[0] // empty' 2>/dev/null || true)}}"
  [ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
  [ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
  [ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
  bash "$STACKS_ROOT/scripts/pipeline/catalog.sh" queue
  ```

  Empty output means nothing is queued — tell the user and stop. Otherwise **run Steps 2–9 once per stack in the printed order** (each stack is an independent cataloging run; commit per stack at Step 9 so a failure mid-queue leaves prior stacks clean). `--from` is not available in this mode (it needs an explicit stack).

For each stack to catalog, do Steps 2–9.

## Step 2: Prep — stage, convert, enumerate, shard (`catalog.sh prep`)

`prep` does everything deterministic before the first agent: resolve+cd the library, stage `--from` sources (collision-safe copy of the supported types), convert non-text sources (PDF/Office → text sidecars, images/scanned/unknown skipped-and-reported), enumerate `sources/incoming/` (the new-source set), fail early on `(`/`)` in a filename (breaks the index parser), and write the W1 manifest (`dev/extractions/dispatch-w1.tsv`) + `run.env` with `RUN_ID_W1`.

```bash
STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/settings.json" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | jq -rs '[.[] | (.extraKnownMarketplaces.stacks.source.path)?, (.plugins["stacks@stacks"][0].installPath)?] | map(strings) | .[0] // empty' 2>/dev/null || true)}}"
[ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
[ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
[ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
bash "$STACKS_ROOT/scripts/pipeline/catalog.sh" prep {stack}
# or, staging first:  ... prep {stack} --from {path}
```

Surface prep's output to the operator: the staging report (how many staged/skipped and why), the converter's `PASSTHROUGH`/`CONVERTED`/`SKIPPED` lines (a silently-skipped source reads as covered while being absent), and the new-source count. A `CATALOG_NOOP` line means `incoming/` is empty after staging — nothing to catalog for this stack; move to the next (or stop). A non-zero exit (bad `--from`, a paren filename, missing stack) prints the reason and stops.

## Step 3: Read STACK.md

Read `{stack}/STACK.md` for the source hierarchy (tier rankings for conflict resolution), the scope section (what belongs / the "What does not belong" discard test), and the filing rules. The W1 agents need the hierarchy and scope; you need the filing rules only if you later resolve an ambiguous publisher by hand.

## Step 4: W1 — Dispatch one source-extractor per source

`prep` sharded the sources one-per-agent — per-source isolation on purpose: bundling sources into one agent bleeds claims across them (a claim from source A attributed to a concept first seen in source B). Read the manifest `dev/extractions/dispatch-w1.tsv` — each row is `batch_tag<TAB>source_path`. **In a single message, emit one `Agent` tool call per manifest row**, `subagent_type` = `stacks:source-extractor`. Parallel dispatch — never sequential. Each agent prompt names:

- its **`batch_id`** = the string `batch-` followed by column 1's numeric tag (column 1 holds `1`, `2`, …, so `batch_id` is `batch-1`, `batch-2`, …), which fixes its output path `dev/extractions/{batch_id}-concepts.md`,
- its assigned **source path** (column 2),
- the path to `{stack}/STACK.md` (source hierarchy + scope),
- `{stack}/index.md`'s `## Articles` map — the authoritative slug set (one entry per article) and the `slug — scope` routing lines that say what each existing article already covers. The scope lines are the reuse-vs-mint decision surface: a concept that falls within an existing article's *described scope* reuses that slug instead of minting a new one, which is what stops a rich source fragmenting one article into several new sub-topic slugs (stacks#106). If `index.md` has no `## Articles` map yet (first catalog run, no articles), fall back to the existing `{stack}/articles/` directory listing as the slug set.

Dispatch each extractor with `run_in_background: true` so the session stays responsive during the multi-minute agent runtime; the harness delivers a completion notification per agent. This phase is a barrier: do not run Step 5 (`catalog.sh gate-w1`) until every dispatched extractor has reported completion. Backgrounding preserves the barrier (you still wait for all agents) while keeping the session interactive and letting you interleave other work.

## Step 5: Gate W1 (`catalog.sh gate-w1`)

After all extractors return, gate the batch. One source maps 1:1 to one `batch-<tag>-concepts.md`, so a missing/empty/stale concept file fails **by path** — that presence check is the per-source coverage.

```bash
STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/settings.json" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | jq -rs '[.[] | (.extraKnownMarketplaces.stacks.source.path)?, (.plugins["stacks@stacks"][0].installPath)?] | map(strings) | .[0] // empty' 2>/dev/null || true)}}"
[ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
[ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
[ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
bash "$STACKS_ROOT/scripts/pipeline/catalog.sh" gate-w1 {stack}
```

A non-zero exit names the ungated batch file(s) — an extractor that wrote nothing or wrote a stale file. Surface it and stop.

## Step 5.5: Local-extraction shadow + advisory verify (verify-and-fix rollout, opt-in — #109)

**Runs only when `STACKS_LOCAL_SHADOW=1` is set.** Default runs skip it. This is the extraction analog of the synthesis advisory (Step 8.5/8.6): it grades whether the cheap local tier could do W1 extraction behind the harness — the recipe is the cheap tier proposes concepts + slugs, the deterministic **slug pre-match gate** owns exact/normalized collisions, and the cloud **`extraction-verifier`** owns the semantic reuse-vs-mint judgment (the over-mint the gate can't see). **The cloud `source-extractor` output that feeds W1b/dedup is authoritative and untouched; this only observes.** Runs after `gate-w1` and before `finish` clears `dispatch-w1.tsv`.

First, the local extraction + gate pass (writes a NEAR/NEW survivor manifest; exact-collision reuses are harness-resolved and never sent to the cloud):

```bash
if [ "${STACKS_LOCAL_SHADOW:-0}" = "1" ]; then
  STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/settings.json" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | jq -rs '[.[] | (.extraKnownMarketplaces.stacks.source.path)?, (.plugins["stacks@stacks"][0].installPath)?] | map(strings) | .[0] // empty' 2>/dev/null || true)}}"
  [ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
  [ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
  [ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
  bash "$STACKS_ROOT/dev/experiments/model-tier/harness/shadow-extract-run.sh" {stack} || echo "extraction shadow returned non-zero — non-fatal, continuing"
fi
```

Non-fatal by design (breathless unreachable → every source logs a failure and the run proceeds). Read the `SHADOW_EXTRACT_SUMMARY` line for the sources/candidates/survivors counts, and the survivor manifest at `$STACKS_ROOT/dev/experiments/model-tier/live-diffs/extractions/survivors.tsv` (rows: `slug<TAB>local_decision<TAB>prematch`).

Then the advisory verify: **clear the previous batch's top-level grades** (`mkdir -p "$STACKS_ROOT/dev/experiments/model-tier/live-diffs/extract-verify" && find "$STACKS_ROOT/dev/experiments/model-tier/live-diffs/extract-verify" -maxdepth 1 -type f -name '*.json' -delete`; its subfolders are tracked evidence and stay), then for each survivor row dispatch one **`stacks:extraction-verifier`** agent (cloud sonnet, ≤25 per message). Give each agent absolute paths, scope pinned to: the stack's scope map `{LIBRARY}/{stack}/index.md` and articles dir `{LIBRARY}/{stack}/articles/` (the reuse test), the survivor's `slug`/`local_decision`/`prematch`, and the grade JSON to write at `$STACKS_ROOT/dev/experiments/model-tier/live-diffs/extract-verify/{slug}.json`. It verifies each NEAR/NEW candidate against the scope map (fragment → `reuse:<slug>`, genuine gap → `NEW`) and never edits any extraction, article, or index. After the wave returns, aggregate:

```bash
STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/settings.json" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | jq -rs '[.[] | (.extraKnownMarketplaces.stacks.source.path)?, (.plugins["stacks@stacks"][0].installPath)?] | map(strings) | .[0] // empty' 2>/dev/null || true)}}"
[ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
[ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
[ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
bash "$STACKS_ROOT/dev/experiments/model-tier/harness/extraction-verify-summary.sh" \
  "$STACKS_ROOT/dev/experiments/model-tier/live-diffs/extract-verify" || true
```

Read the `over-mint caught` / `genuine new` line — how many of the local tier's mints were fragments the gate+verifier would catch before shipping vs real gaps. Advisory only; `finish` proceeds regardless.

## Step 6: Dedup + near-dup review (`catalog.sh dedup`)

`dedup` runs the deterministic W1b merge (union `source_paths` per slug, classify each unique slug new/updated, flag near-duplicate titles), asserts the merged output's shape, and writes the W2 manifest (`dev/extractions/dispatch-w2.tsv`, one slug per row) + `run.env` with `RUN_ID_W2`.

```bash
STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/settings.json" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | jq -rs '[.[] | (.extraKnownMarketplaces.stacks.source.path)?, (.plugins["stacks@stacks"][0].installPath)?] | map(strings) | .[0] // empty' 2>/dev/null || true)}}"
[ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
[ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
[ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
bash "$STACKS_ROOT/scripts/pipeline/catalog.sh" dedup {stack}
```

Read its output: the unique-concept count (new/updated split), the wave plan, and `NEAR_DUP_PAIRS`.

**Near-dup review (stacks#78) — do this before W2 dispatch.** Exact-slug dedup cannot catch two NEW slugs that are the same concept under different names (parallel extractors are blind to each other). If `dedup` printed a non-empty `NEAR_DUP_PAIRS=` line, STOP: for each `slugA~slugB` pair, read the two `dev/extractions/_dedup-{slug}.md` blocks and decide — **same concept** → merge them (fold one block's `source_paths` and claims into the other, `rm` the absorbed `_dedup-{slug}.md`, and delete the absorbed slug's row from `dev/extractions/dispatch-w2.tsv`) so W2 emits one article, not two stubs; **genuinely distinct** → leave both. Report-and-decide, never auto-merge: a wrong merge buries a lower-tier claim under a higher-tier block.

## Step 7: W2 — Dispatch one article-synthesizer per slug

Read `dev/extractions/dispatch-w2.tsv` — each row is `wave_tag<TAB>slug`. Article-synthesizer is 1-per-slug. Dispatch in waves grouped by `wave_tag` (the cap keeps any one message from overwhelming the harness): **for each wave, in a single message emit one `Agent` call per slug in that wave**, `subagent_type` = `stacks:article-synthesizer`; run waves sequentially. Each agent prompt names:

- `{stack}/dev/extractions/_dedup-{slug}.md` (the self-contained concept block),
- `{stack}/articles/{slug}.md` **only if** the slug is in `dedup`'s `Updated slugs` list (an update — the agent reads the existing article and revises it; new slugs have no such file),
- `{stack}/STACK.md` (source hierarchy + `allowed_tags`),
- `{stack}/index.md`'s `## Articles` map — the `[[slug|title]] — scope` routing lines that say what each sibling article already covers. This is the content-boundary surface (stacks#110): it tells the synthesizer what NOT to restate (a sibling's territory) and what it can cross-link inline instead of re-explaining. If `index.md` has no `## Articles` map yet (first catalog run, no articles), the agent writes without it — there are no siblings to bound against.

When `STACKS_LOCAL_SHADOW=1` is set, note each synthesizer's total tokens from its completion; Step 8.6 compares them with the review cost.

Within each wave, dispatch the synthesizers with `run_in_background: true` so the session stays responsive during the multi-minute agent runtime; the harness delivers a completion notification per agent. Each wave is a barrier: wait for every synthesizer in the wave to report completion before starting the next wave, and do not run Step 8 (`catalog.sh gate-w2`) until the final wave's agents have all completed. Backgrounding preserves the barrier while keeping the session interactive.

## Step 8: Gate W2 (`catalog.sh gate-w2`)

After all waves return, gate the articles. 1 slug maps 1:1 to `articles/{slug}.md`, so a missing article (a synthesizer that skipped its slug) or an unrewritten update (mtime older than this run) fails **by path**.

```bash
STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/settings.json" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | jq -rs '[.[] | (.extraKnownMarketplaces.stacks.source.path)?, (.plugins["stacks@stacks"][0].installPath)?] | map(strings) | .[0] // empty' 2>/dev/null || true)}}"
[ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
[ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
[ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
bash "$STACKS_ROOT/scripts/pipeline/catalog.sh" gate-w2 {stack}
```

A non-zero exit names the ungated article(s). Surface it and stop; the sources stay in `incoming/` (finish is not reached) and the next run retries.

## Step 8.5: Local-model shadow diff (pilot, opt-in — #109)

**Runs only when `STACKS_LOCAL_SHADOW=1` is set in the environment.** Default catalog runs skip this entirely: the pilot doubles synthesis work and exists to grade the local drafter against the cloud writer, not to ship anything. When enabled, after `gate-w2` passes and before `finish`, it runs the local drafter (the breathless vLLM server through `local-infer.sh`; `STACKS_LOCAL_URL` and `STACKS_LOCAL_MODEL` override the defaults) on each W2 concept block, 4 at a time. Each draft gets the same inputs the cloud writer had: the stack's `STACK.md`, its `index.md` scope map, and on an update the pre-update article that `dedup` saved as `_prior-{slug}.md`. The harness then applies the mechanical filters (tag vocabulary, `[source: X]` to `[X]`, the deterministic refusal gate) and writes the drafts and a log of one record per slug into this run's own folder, `dev/experiments/model-tier/live-diffs/runs/<RUN_ID_W2>-<stack>-<label>/`, printed as `RUN_DIR=`. The label comes from `STACKS_RUN_LABEL` (default `default`) and names a variant, so variants of one batch run side by side without sharing a file; a folder already in use is refused, so a rerun needs a new label. **The shipped cloud article is authoritative and untouched; this only observes.**

```bash
if [ "${STACKS_LOCAL_SHADOW:-0}" = "1" ]; then
  STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/settings.json" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | jq -rs '[.[] | (.extraKnownMarketplaces.stacks.source.path)?, (.plugins["stacks@stacks"][0].installPath)?] | map(strings) | .[0] // empty' 2>/dev/null || true)}}"
  [ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
  [ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
  [ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
  bash "$STACKS_ROOT/dev/experiments/model-tier/harness/shadow-synth-run.sh" {stack} || echo "shadow pilot returned non-zero — non-fatal, continuing to finish"
fi
```

Non-fatal by design: a failed local call logs a `status:"local-inference-failed"` record, a local refusal logs `status:"refused"`, and neither blocks `finish`. Read the `SHADOW_SUMMARY` line for the shadowed/skipped/failed counts. If breathless is unreachable, every slug logs a failure and the run proceeds normally.

### Step 8.6: Advisory verify of the local drafts (verify-and-fix rollout, opt-in — #109)

**Also gated on `STACKS_LOCAL_SHADOW=1`, and only after Step 8.5 ran.** This is the advisory window before flipping synthesis to verify-and-fix (`dev/specs/verify-and-fix.md`): it measures whether, if the local draft became the article and the cloud reviewer fixed only its defects, every article would clear the synthesis floors at lower cloud cost. **Nothing here changes `articles/`.**

Grades, repairs and token rows go into the same run folder as its drafts; the summary also ignores any file written before the batch's `RUN_ID_W2`. Build the two manifests, one row per slug:

```bash
STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/settings.json" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | jq -rs '[.[] | (.extraKnownMarketplaces.stacks.source.path)?, (.plugins["stacks@stacks"][0].installPath)?] | map(strings) | .[0] // empty' 2>/dev/null || true)}}"
[ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
[ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
[ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
RUN_DIR=$(bash "$STACKS_ROOT/dev/experiments/model-tier/harness/run-dir.sh" {stack}) || exit 1
bash "$STACKS_ROOT/dev/experiments/model-tier/harness/verify-manifest.sh" {stack} local > "$RUN_DIR/verify/manifest-local.tsv"
bash "$STACKS_ROOT/dev/experiments/model-tier/harness/verify-manifest.sh" {stack} cloud > "$RUN_DIR/verify/manifest-cloud.tsv"
echo "RUN_DIR=$RUN_DIR"
```

Dispatch one **`stacks:article-verifier`** agent per manifest, or per 8 rows when a manifest is longer (split it into files of 8 rows; about 2,000 output tokens per repaired row keeps each agent well under the output cap). Give each agent the manifest path, `{LIBRARY}/{stack}/STACK.md` and `{LIBRARY}/{stack}/index.md`. The local manifest grades each local draft and repairs a scratch copy; the cloud manifest grades the shipped cloud article on the same block, grade only. On Codex, dispatch them as using-stacks behavior 7 says.

When the agents return, write `$RUN_DIR/verify/tokens.tsv`, one row per slug with a local grade: `slug<TAB>synthesizer total tokens (Step 7)<TAB>verifier share`. A verifier agent's share for each of its N rows is its total divided by N, rounded down, with the remainder added one token at a time to its first rows, so the shares sum to the agent's total. Then aggregate over every dispatched slug; a missing draft, refusal, failed call, missing grade or rejected grade counts as a failure:

```bash
STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/settings.json" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | jq -rs '[.[] | (.extraKnownMarketplaces.stacks.source.path)?, (.plugins["stacks@stacks"][0].installPath)?] | map(strings) | .[0] // empty' 2>/dev/null || true)}}"
[ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
[ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
[ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
LIB=$(bash "$STACKS_ROOT/scripts/resolve-library.sh") || exit 1
RUN_DIR=$(bash "$STACKS_ROOT/dev/experiments/model-tier/harness/run-dir.sh" {stack}) || exit 1
bash "$STACKS_ROOT/dev/experiments/model-tier/harness/synth-verify-summary.sh" \
  "$LIB/{stack}/dev/extractions" "$RUN_DIR" "$RUN_DIR/verify/tokens.tsv" || true
```

Read the `PROMOTE:` line. Promotion needs every dispatched slug clearing after repair and the review tokens below the write tokens; then read a sample of drafts beside their cloud articles (the `cloud article clears` line is the same-block baseline) before flipping. Advisory only; `finish` proceeds regardless.

## Step 9: Finish, log, commit (`catalog.sh finish`)

`finish` runs the post-synthesis deterministic tail: tag-drift enforcement (halts before filing if any article carries an out-of-vocabulary tag, so its source stays in `incoming/` for the next run), W3 source filing (each `incoming/` source moved to its publisher dir with citations rewritten; a source with no `publisher:` field files under `sources/unknown/` and is reported), W4 MoC regeneration. It does **not** delete the run's working files (`batch-*-concepts.md`, `_dedup*.md`, `dispatch-w1.tsv`/`dispatch-w2.tsv`, `run.env`) — those are this run's audit trail (which sources were dispatched, what each extractor found, which slugs were reuse vs mint) and stay on disk for the operator/auditor to read after `finish`; the next `prep` on this stack clears them to start its own manifest clean, so the retention window is until this stack's next catalog run, not indefinite (issue #130). It prints a `CATALOG_SUMMARY: sources=… new=… updated=… unfiled=…` line.

```bash
STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/settings.json" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | jq -rs '[.[] | (.extraKnownMarketplaces.stacks.source.path)?, (.plugins["stacks@stacks"][0].installPath)?] | map(strings) | .[0] // empty' 2>/dev/null || true)}}"
[ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
[ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
[ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
bash "$STACKS_ROOT/scripts/pipeline/catalog.sh" finish {stack}
```

A non-zero exit with `TAG_DRIFT:` lines means an article's tags left the `allowed_tags:` vocabulary — surface it, and tell the operator to fix the article tag or the vocabulary list before re-running (the source stayed in `incoming/`). Otherwise read the `CATALOG_SUMMARY` counts for the log+commit.

Prepend a log entry and commit. Shell state does not survive between these blocks, so re-resolve the library here — substitute `{stack}` and the counts from `CATALOG_SUMMARY`:

```bash
STACKS_ROOT="${STACKS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cat "$HOME/.claude/settings.json" "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | jq -rs '[.[] | (.extraKnownMarketplaces.stacks.source.path)?, (.plugins["stacks@stacks"][0].installPath)?] | map(strings) | .[0] // empty' 2>/dev/null || true)}}"
[ -n "$STACKS_ROOT" ] || [ "${PI_CODING_AGENT:-}" != true ] || STACKS_ROOT=$(skill=$(readlink -f "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills/using-stacks" 2>/dev/null || true); root=${skill%/skills/using-stacks}; for root in "$root" "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/git/github.com/chuggies510/stacks" "$PWD/.pi/git/github.com/chuggies510/stacks"; do [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ] && { printf '%s\n' "$root"; break; }; done; true)
[ -n "$STACKS_ROOT" ] || STACKS_ROOT=$(base="${CODEX_PLUGIN_CACHE:-${CODEX_HOME:-$HOME/.codex}/plugins/cache}/stacks/stacks"; { find "$base" -type d -print 2>/dev/null || true; } | while IFS= read -r root; do if [ "${root%/*}" = "$base" ] && [ -f "$root/scripts/resolve-library.sh" ] && [ -f "$root/skills/using-stacks/SKILL.md" ]; then printf '%s\n' "$root"; fi; done | sort -V | tail -1)
[ -f "$STACKS_ROOT/scripts/resolve-library.sh" ] && [ -f "$STACKS_ROOT/skills/using-stacks/SKILL.md" ] || { printf '%s\n' "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." >&2; exit 1; }
LIBRARY=$(bash "$STACKS_ROOT/scripts/resolve-library.sh") && cd "$LIBRARY" || exit 1
NEW_ENTRY="## [$(date +%Y-%m-%d)] catalog | {sources} new sources, {new} articles created, {updated} updated
Sources processed: {sources}. New articles: {new}. Updated articles: {updated}."
{ printf '%s\n\n' "$NEW_ENTRY"; cat "{stack}/log.md"; } > /tmp/stacks-log.tmp
mv /tmp/stacks-log.tmp "{stack}/log.md"
git add "{stack}/"
git commit -m "feat({stack}): catalog {sources} sources, {new} new articles, {updated} updated"
```

Report to the user: sources processed, articles created vs updated, any sources filed under `sources/unknown/` (no publisher field) or left in `incoming/` (failed a gate), and suggest `/stacks:audit-stack {stack}` next if 2+ articles exist.
