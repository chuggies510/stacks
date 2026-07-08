#!/usr/bin/env bash
set -euo pipefail

# Catalog-sources pipeline orchestration — the deterministic control flow that
# used to live in catalog-sources SKILL.md Bash blocks, now one checked-in script
# with phase subcommands. The two model dispatches (W1 source-extractor,
# W2 article-synthesizer) and the interactive near-dup review stay in the skill as
# prose; everything mechanical (arg parse, --from staging, convert, enum, paren
# gate, sharding, dedup, gating, tag-drift, source filing, MoC, cleanup) is here.
# Mirrors scripts/pipeline/{enrich,audit}.sh (#87).
#
# Usage:
#   bash catalog.sh queue                        # stacks with queued incoming/ (no stack given)
#   bash catalog.sh prep    <stack> [--from P]   # Steps 1-5-setup: stage, convert, W0, W1 manifest
#   bash catalog.sh gate-w1 <stack>              # Step 5-gate: gate the source-extractor batch files
#   bash catalog.sh dedup   <stack>              # Step 5.5: W1b dedup + W2 manifest + near-dup report
#   bash catalog.sh gate-w2 <stack>              # Step 5.75-gate: gate the synthesized articles
#   bash catalog.sh finish  <stack>              # Steps 6-8: tag-drift, W3 filing, W4 MoC, cleanup
#   bash catalog.sh --self-check
#
# Phase contract (subcommands because a bash script can't spawn subagents, so the
# pipeline is prep -> W1 dispatch -> gate-w1 -> dedup -> [near-dup review] ->
# W2 dispatch -> gate-w2 -> finish, split at each dispatch boundary):
#
#   queue    (no stack) List stacks with >0 files in sources/incoming/, largest
#            first, one per line. The multi-stack auto-queue when the skill is run
#            with no stack argument; empty output = nothing to catalog.
#   prep     Resolve+cd the library, optionally stage --from sources (collision-
#            safe copy), convert non-text sources to text sidecars, enumerate
#            sources/incoming/ (the new-source set — W3 moves them out on success),
#            fail on '(' / ')' in a filename (breaks the index parser), and write
#            the W1 manifest (dispatch-w1.tsv) + run.env with RUN_ID_W1. Clears
#            stale batch/_dedup working files. Prints the per-source batch mapping
#            the dispatch prose reads. Exits 0 with CATALOG_NOOP when incoming/ is
#            empty (skill skips to the next stack).
#   gate-w1  Re-read RUN_ID_W1, gate every expected batch-<tag>-concepts.md
#            (gate-batch.sh: write-or-fail + concept-batch shape). One source maps
#            1:1 to one batch file, so a missing/empty/stale file fails BY PATH —
#            that path-level presence check IS this pipeline's per-source coverage
#            (no check-coverage.sh: nothing here reuses one output file for many
#            items the way audit/enrich do).
#   dedup    Run dedup-extractions.py (W1b merge), assert _dedup.md + _dedup-meta
#            shape, then write the W2 manifest (dispatch-w2.tsv, one slug per row,
#            grouped into WAVE_CAP-sized waves) and refresh run.env with N_NEW/
#            N_UPDATED/UPDATED_SLUGS + RUN_ID_W2 (captured HERE, before any W2
#            dispatch, so it is a valid freshness floor for every wave). Prints the
#            near-dup pairs for the interactive review and the wave dispatch plan.
#   gate-w2  Re-read RUN_ID_W2, gate every expected articles/<slug>.md
#            (gate-batch.sh: write-or-fail + article-md shape). 1 slug ↔ 1 article,
#            so a missing/stale article (a synthesizer that skipped its slug, or an
#            UPDATED article the agent never rewrote → mtime older than RUN_ID_W2)
#            fails BY PATH. Again the presence check is the coverage.
#   finish   Enforce tag drift (normalize-tags.sh — HALTS before filing so a
#            drifted article's source stays in incoming/ for the next run), file
#            each incoming/ source to its publisher dir (W3) rewriting the now-moved
#            citations, regenerate the MoC (W4), print CATALOG_SUMMARY counts for
#            the skill's log+commit, then remove the transient run/working files.
#            Only reached after gate-w2 passes, so every synthesized article is
#            present — all incoming sources file. A missing publisher field files
#            the source under sources/unknown/ and is reported (unfiled=N), never
#            an interactive stall.
#
# State crosses phases ONLY through these files under dev/extractions/, never
# shell env (the #72 fix — a var set in one SKILL.md Bash block is empty in the
# next; the batch/_dedup working files already live here, so run-state joins them):
#
#   dev/extractions/run.env          KEY=VAL. RUN_ID_W1/RUN_ID_W2 (dispatch epochs
#                                    + gate-batch freshness floors), STACK,
#                                    N_SOURCES, N_NEW, N_UPDATED, UPDATED_SLUGS,
#                                    WAVE_CAP, DISPATCH paths.
#   dev/extractions/dispatch-w1.tsv  W1 manifest, one row per source:
#                                    batch_tag<TAB>source_path. batch_tag (1-based)
#                                    names the agent's output batch-<tag>-concepts.md.
#   dev/extractions/dispatch-w2.tsv  W2 manifest, one row per unique concept slug:
#                                    wave_tag<TAB>slug. wave_tag groups slugs into
#                                    WAVE_CAP-sized dispatch waves; slug names the
#                                    agent's output articles/<slug>.md.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPERS="$SCRIPT_DIR/.."   # scripts/ — where the shared helpers live

WAVE_CAP=25   # article-synthesizer agents per W2 dispatch wave — a harness message-
              # size ceiling only (matches the prior orchestrator's W2_WAVE_CAP), NOT
              # a gating unit: coverage is per-slug file presence across all waves.

# Source file extensions staged from a --from path (the convert stage turns the
# document formats into text; images/scanned PDFs/unknown binaries skip-and-report).
STAGE_EXTS=(md txt html htm pdf docx doc odt rtf xlsx xls ods pptx ppt)

die() { echo "ERROR: $*" >&2; exit 1; }

# Echo the resolved library's absolute path, or fail non-zero. Every phase cds
# itself (self-contained — never assumes an earlier phase's cd survived). Callers
# MUST capture-then-cd, never `cd "$(enter_library)"` (on a resolve failure that
# is `cd ""`, which succeeds as a no-op and runs in the wrong dir — the #74 footgun).
enter_library() {
  bash "$HELPERS/resolve-library.sh"
}

# Count non-.gitkeep files directly in a stack's incoming/ (the new-source set).
incoming_count() {
  find "$1/sources/incoming" -type f ! -name '.gitkeep' 2>/dev/null | wc -l | tr -d ' '
}

# --- queue ------------------------------------------------------------------
# No stack given → every stack with queued incoming sources, largest batch first.
phase_queue() {
  local LIB; LIB=$(enter_library) || die "could not resolve the library."
  cd "$LIB" || die "could not cd into library: $LIB"
  local d name count
  for d in */STACK.md; do
    [[ -e "$d" ]] || continue
    name=$(dirname "$d")
    count=$(incoming_count "$name")
    [[ "$count" -gt 0 ]] && echo "$count $name"
  done | sort -rn | awk '{print $2}'
}

# --- prep -------------------------------------------------------------------
phase_prep() {
  local STACK="" FROM=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from) shift; FROM="${1:-}"; shift || true ;;
      *)      [[ -z "$STACK" ]] && STACK="$1"; shift ;;
    esac
  done
  [[ -n "$STACK" ]] || die "Specify a stack name. Usage: catalog.sh prep <stack> [--from <path>]"

  local LIB; LIB=$(enter_library) || die "could not resolve the library (no config, and cwd is not a library)."
  cd "$LIB" || die "could not cd into library: $LIB"
  [[ -f "$STACK/STACK.md" ]] || die "Stack '$STACK' not found (no STACK.md). Run /stacks:new-stack $STACK first."

  local INCOMING="$STACK/sources/incoming"
  local DEV="$STACK/dev/extractions"
  local ADEV="$LIB/$DEV"
  mkdir -p "$INCOMING" "$DEV"

  # --- Stage from --from (collision-safe copy of the supported types) ---------
  if [[ -n "$FROM" ]]; then
    FROM="${FROM/#\~/$HOME}"
    [[ -d "$FROM" ]] || die "--from path does not exist: $FROM"
    local find_args=() e first=1
    for e in "${STAGE_EXTS[@]}"; do
      [[ $first -eq 1 ]] || find_args+=(-o); first=0
      find_args+=(-iname "*.$e")
    done
    local staged=0 src dest fn
    while IFS= read -r -d '' src; do
      fn=$(basename "$src")
      dest=$(bash "$HELPERS/collision-dest.sh" "$INCOMING" "$fn")
      cp "$src" "$dest"; staged=$((staged+1))
    done < <(find "$FROM" -type f \( "${find_args[@]}" \) -print0 2>/dev/null)
    local total; total=$(find "$FROM" -type f ! -name '.gitkeep' 2>/dev/null | wc -l | tr -d ' ')
    echo "Staged $staged file(s) from $FROM to $INCOMING/ ($((total - staged)) non-source skipped)."
    [[ "$staged" -ge 1 ]] || die "No source files found in $FROM (supported: ${STAGE_EXTS[*]})."
  fi

  # --- Convert non-text sources to text sidecars (in place) -------------------
  # Runs for direct drops too, not just --from staging: type-awareness lives in
  # the converter, once. Its report (PASSTHROUGH/CONVERTED/SKIPPED) is surfaced so
  # a silently-skipped source is visible.
  bash "$HELPERS/convert-sources.sh" "$INCOMING" "$STACK/sources/.raw"

  # --- W0: enumerate + paren gate --------------------------------------------
  local PARENS; PARENS=$(find "$INCOMING" -type f \( -name '*(*' -o -name '*)*' \) ! -name '.gitkeep' 2>/dev/null)
  [[ -z "$PARENS" ]] || die $'source filename(s) contain "(" or ")" (breaks the index parser); rename before cataloging:\n'"$PARENS"

  local SOURCES=() s
  while IFS= read -r s; do SOURCES+=("$s"); done \
    < <(find "$INCOMING" -type f ! -name '.gitkeep' 2>/dev/null | sort)
  local N=${#SOURCES[@]}
  if [[ "$N" -eq 0 ]]; then
    echo "CATALOG_NOOP: no new sources in $INCOMING (nothing to catalog for $STACK)."
    return 0
  fi

  # Clear stale W1/W2 working files (freshness gate depends on every kept batch
  # file being written strictly after RUN_ID_W1 below).
  rm -f "$DEV"/batch-*-concepts.md "$DEV"/_dedup*.md "$DEV"/_dedup-meta.txt \
        "$DEV"/dispatch-w1.tsv "$DEV"/dispatch-w2.tsv

  # W1 manifest: batch_tag(1-based)<TAB>source_path. One source per batch (per-
  # source isolation — a big slice bleeds claims across sources); batch_tag names
  # the agent's output batch-<tag>-concepts.md.
  local DISPATCH="$DEV/dispatch-w1.tsv"
  : > "$DISPATCH"
  local i
  for i in "${!SOURCES[@]}"; do
    printf '%d\t%s\n' "$((i + 1))" "$LIB/${SOURCES[$i]}" >> "$DISPATCH"
  done

  local RUN_ID_W1; RUN_ID_W1=$(date +%s)
  {
    echo "RUN_ID_W1=$RUN_ID_W1"
    echo "STACK=$STACK"
    echo "N_SOURCES=$N"
    echo "WAVE_CAP=$WAVE_CAP"
    echo "DISPATCH_W1=$ADEV/dispatch-w1.tsv"
    echo "DISPATCH_W2=$ADEV/dispatch-w2.tsv"
  } > "$DEV/run.env"

  echo "New sources: $N.  RUN_ID_W1=$RUN_ID_W1"
  echo "W1 manifest: $ADEV/dispatch-w1.tsv   (batch_tag<TAB>source_path)"
  echo "Stack root:  $LIB/$STACK   (STACK.md has source hierarchy + scope; articles/ for slug reuse)"
  echo "Dispatch one stacks:source-extractor per manifest row: batch_id=batch-<batch_tag>, write dev/extractions/batch-<batch_tag>-concepts.md"
}

# --- gate-w1 ----------------------------------------------------------------
phase_gate_w1() {
  local STACK="${1:-}"; [[ -n "$STACK" ]] || die "Usage: catalog.sh gate-w1 <stack>"
  local LIB; LIB=$(enter_library) || die "could not resolve the library."
  cd "$LIB" || die "could not cd into library: $LIB"
  local DEV="$STACK/dev/extractions"
  [[ -f "$DEV/run.env" ]]         || die "no run.env at $DEV — run 'catalog.sh prep' first."
  [[ -f "$DEV/dispatch-w1.tsv" ]] || die "no dispatch-w1.tsv at $DEV — run 'catalog.sh prep' first."

  local RUN_ID; RUN_ID=$(grep -m1 '^RUN_ID_W1=' "$DEV/run.env" | cut -d= -f2)
  [[ "$RUN_ID" =~ ^[0-9]+$ ]] || die "RUN_ID_W1 missing/garbled in $DEV/run.env"

  # Expected concept file per source (batch_tag col 1). 1 source ↔ 1 file, so
  # gate-batch's per-path write-or-fail IS per-source coverage.
  local FILES=() t
  while IFS= read -r t; do FILES+=("$DEV/batch-$t-concepts.md"); done < <(cut -f1 "$DEV/dispatch-w1.tsv" | sort -un)
  bash "$HELPERS/gate-batch.sh" "$RUN_ID" source-extractor concept-batch "${FILES[@]}"
}

# --- dedup ------------------------------------------------------------------
phase_dedup() {
  local STACK="${1:-}"; [[ -n "$STACK" ]] || die "Usage: catalog.sh dedup <stack>"
  local LIB; LIB=$(enter_library) || die "could not resolve the library."
  cd "$LIB" || die "could not cd into library: $LIB"
  local DEV="$STACK/dev/extractions"
  [[ -f "$DEV/run.env" ]]         || die "no run.env at $DEV — run 'catalog.sh prep' first."
  [[ -f "$DEV/dispatch-w1.tsv" ]] || die "no dispatch-w1.tsv at $DEV — run 'catalog.sh prep' first."
  local N_SOURCES; N_SOURCES=$(grep -m1 '^N_SOURCES=' "$DEV/run.env" | cut -d= -f2)

  # Only the W1-dispatched batch files may feed the merge. dedup-extractions.py
  # globs every batch-*-concepts.md, and gate-w1 ignores files outside the manifest
  # set — so an extra batch-<tag>-concepts.md (a misbehaving extractor that wrote
  # an unassigned tag) would silently leak its slugs into W2. Reject it here (the
  # manifest is authoritative, not the live tree — same defense as audit's finish).
  local EXPECTED; EXPECTED=$(cut -f1 "$DEV/dispatch-w1.tsv" | sort -u | sed 's#^#batch-#; s#$#-concepts.md#')
  local UNEXPECTED=() bf bn
  shopt -s nullglob
  for bf in "$DEV"/batch-*-concepts.md; do
    bn=$(basename "$bf")
    grep -qxF "$bn" <<<"$EXPECTED" || UNEXPECTED+=("$bn")
  done
  shopt -u nullglob
  [[ ${#UNEXPECTED[@]} -eq 0 ]] || die "batch file(s) not in the W1 manifest (would leak into W2): ${UNEXPECTED[*]}"

  # W1b merge: union source_paths per slug, classify new/updated, near-dup flag.
  python3 "$HELPERS/dedup-extractions.py" "$DEV" "$DEV/_dedup.md"
  bash "$HELPERS/assert-structure.sh" "$DEV/_dedup.md" dedup-md dedup \
    || die "dedup output malformed — no concept blocks in _dedup.md"
  bash "$HELPERS/assert-structure.sh" "$DEV/_dedup-meta.txt" dedup-meta dedup \
    || die "dedup meta malformed — missing/empty ALL_SLUGS"

  # Read the merge meta (grep, not source — a title with shell metacharacters
  # must not execute).
  local ALL_SLUGS N_NEW N_UPDATED UPDATED_SLUGS NEAR_DUP_PAIRS
  ALL_SLUGS=$(grep -m1 '^ALL_SLUGS=' "$DEV/_dedup-meta.txt" | cut -d= -f2-)
  N_NEW=$(grep -m1 '^N_NEW=' "$DEV/_dedup-meta.txt" | cut -d= -f2)
  N_UPDATED=$(grep -m1 '^N_UPDATED=' "$DEV/_dedup-meta.txt" | cut -d= -f2)
  UPDATED_SLUGS=$(grep -m1 '^UPDATED_SLUGS=' "$DEV/_dedup-meta.txt" | cut -d= -f2-)
  NEAR_DUP_PAIRS=$(grep -m1 '^NEAR_DUP_PAIRS=' "$DEV/_dedup-meta.txt" | cut -d= -f2-)

  # W2 manifest: one slug per row, grouped into WAVE_CAP waves. wave_tag is a
  # dispatch-batching convenience for the skill, NOT a gating unit.
  local DISPATCH="$DEV/dispatch-w2.tsv"; : > "$DISPATCH"
  local i=0 slug
  for slug in $ALL_SLUGS; do
    printf '%d\t%s\n' "$((i / WAVE_CAP))" "$slug" >> "$DISPATCH"
    i=$((i + 1))
  done
  [[ "$i" -ge 1 ]] || die "dedup produced 0 concept slugs — nothing to synthesize."

  # RUN_ID_W2 captured HERE, before any wave dispatches → a valid freshness floor
  # for every wave's articles (each wave writes strictly after this).
  # ponytail: one floor for all waves, not per-wave. Ceiling: if an UPDATED article
  # is externally touched (an operator edit, another process) between this capture
  # and its later wave, a synthesizer that then skips it still passes gate-w2 (mtime
  # > this floor). Per-wave epochs would narrow — not close — that window at the cost
  # of re-invoking the script per wave. Sound for the normal closed-world run; revisit
  # only if mid-run external mutation becomes real.
  local RUN_ID_W2; RUN_ID_W2=$(date +%s)
  {
    echo "RUN_ID_W2=$RUN_ID_W2"
    echo "STACK=$STACK"
    echo "N_SOURCES=$N_SOURCES"
    echo "N_NEW=$N_NEW"
    echo "N_UPDATED=$N_UPDATED"
    echo "UPDATED_SLUGS=$UPDATED_SLUGS"
    echo "WAVE_CAP=$WAVE_CAP"
    echo "DISPATCH_W2=$LIB/$DISPATCH"
  } > "$DEV/run.env"

  local N_WAVES; N_WAVES=$(cut -f1 "$DISPATCH" | sort -un | wc -l | tr -d ' ')
  echo "Unique concepts: $i ($N_NEW new, $N_UPDATED updated).  Waves: $N_WAVES (cap $WAVE_CAP).  RUN_ID_W2=$RUN_ID_W2"
  echo "W2 manifest: $LIB/$DISPATCH   (wave_tag<TAB>slug)"
  echo "Updated slugs (dispatch WITH the existing articles/<slug>.md as input): ${UPDATED_SLUGS:-none}"
  echo "Per-slug concept blocks: $LIB/$DEV/_dedup-<slug>.md"
  if [[ -n "$NEAR_DUP_PAIRS" ]]; then
    echo "NEAR_DUP_PAIRS=$NEAR_DUP_PAIRS"
    echo "^ REVIEW before W2 dispatch: read each pair's _dedup-<slug>.md; if same concept, merge and drop one slug from dispatch-w2.tsv; if distinct, leave both."
  else
    echo "NEAR_DUP_PAIRS= (none)"
  fi
  echo "Dispatch one stacks:article-synthesizer per slug (≤$WAVE_CAP per message); write articles/<slug>.md"
}

# --- gate-w2 ----------------------------------------------------------------
phase_gate_w2() {
  local STACK="${1:-}"; [[ -n "$STACK" ]] || die "Usage: catalog.sh gate-w2 <stack>"
  local LIB; LIB=$(enter_library) || die "could not resolve the library."
  cd "$LIB" || die "could not cd into library: $LIB"
  local DEV="$STACK/dev/extractions"
  [[ -f "$DEV/run.env" ]]         || die "no run.env at $DEV — run 'catalog.sh dedup' first."
  [[ -f "$DEV/dispatch-w2.tsv" ]] || die "no dispatch-w2.tsv at $DEV — run 'catalog.sh dedup' first."

  local RUN_ID; RUN_ID=$(grep -m1 '^RUN_ID_W2=' "$DEV/run.env" | cut -d= -f2)
  [[ "$RUN_ID" =~ ^[0-9]+$ ]] || die "RUN_ID_W2 missing/garbled in $DEV/run.env"

  # Expected article per slug (col 2). 1 slug ↔ 1 file — path presence = coverage.
  local FILES=() slug
  while IFS= read -r slug; do FILES+=("$STACK/articles/$slug.md"); done < <(cut -f2 "$DEV/dispatch-w2.tsv")
  bash "$HELPERS/gate-batch.sh" "$RUN_ID" article-synthesizer article-md "${FILES[@]}"
}

# --- finish -----------------------------------------------------------------
phase_finish() {
  local STACK="${1:-}"; [[ -n "$STACK" ]] || die "Usage: catalog.sh finish <stack>"
  local LIB; LIB=$(enter_library) || die "could not resolve the library."
  cd "$LIB" || die "could not cd into library: $LIB"
  local DEV="$STACK/dev/extractions"
  [[ -f "$DEV/run.env" ]]         || die "no run.env at $DEV — run the earlier phases first."
  [[ -f "$DEV/dispatch-w1.tsv" ]] || die "no dispatch-w1.tsv at $DEV — run 'catalog.sh prep' first."
  [[ -f "$DEV/dispatch-w2.tsv" ]] || die "no dispatch-w2.tsv at $DEV — run 'catalog.sh dedup' (then W2 + gate-w2) before finish."

  # finish must NOT trust that gate-w2 ran — it can be invoked standalone, and a
  # prep->dedup->finish path would otherwise file sources against an empty
  # articles/. Re-assert every dispatched slug has its article BEFORE moving any
  # source out of incoming/ (a move is not rolled back).
  local W2SLUGS=() slug MISS=()
  while IFS= read -r slug; do W2SLUGS+=("$slug"); [[ -f "$STACK/articles/$slug.md" ]] || MISS+=("$slug.md"); done < <(cut -f2 "$DEV/dispatch-w2.tsv")
  [[ ${#MISS[@]} -eq 0 ]] || die "finish: article(s) missing (run gate-w2 first): ${MISS[*]}"

  # W2 tag-drift gate. HALTS before W3 so a drifted article's source stays in
  # incoming/ for the next run (after the operator fixes the tag or vocabulary).
  bash "$HELPERS/normalize-tags.sh" "$STACK" \
    || die "tag drift (see TAG_DRIFT: lines) — fix the article tag or STACK.md allowed_tags, then re-run. Sources stay in incoming/."

  # Counts: recompute from the (possibly operator-edited after a near-dup merge)
  # LIVE manifests, not stale run.env numbers — a merge drops a W2 row, so a
  # run.env N_NEW would overcount. N_SOURCES = W1 dispatched rows; the new/updated
  # split is the live W2 slug set intersected with UPDATED_SLUGS.
  local N_SOURCES; N_SOURCES=$(grep -c . "$DEV/dispatch-w1.tsv" || true)
  local UPDATED_SLUGS; UPDATED_SLUGS=$(grep -m1 '^UPDATED_SLUGS=' "$DEV/run.env" | cut -d= -f2- || true)
  local N_TOTAL N_UPDATED=0 N_NEW
  N_TOTAL=$(cut -f2 "$DEV/dispatch-w2.tsv" | sort -u | grep -c . || true)
  for slug in $(cut -f2 "$DEV/dispatch-w2.tsv" | sort -u); do
    case " $UPDATED_SLUGS " in *" $slug "*) N_UPDATED=$((N_UPDATED + 1)) ;; esac
  done
  N_NEW=$((N_TOTAL - N_UPDATED))

  # W3: file ONLY the W1-dispatched sources (manifest col 2 = incoming path at prep
  # time), never a bare `find incoming` — a source dropped into incoming/ AFTER prep
  # is not part of this run and must stay queued, not be moved out uncataloged.
  local UNFILED=0 src fn publisher pub dest
  while IFS= read -r src; do
    [[ -z "$src" ]] && continue
    [[ -f "$src" ]] || continue   # already filed (idempotent re-run) — skip
    fn=$(basename "$src")
    # Full value after `publisher:` (awk '{print $2}' truncated a multi-word
    # publisher like "U.S. Department of Energy" to "U.S."); normalize-publisher
    # slugifies spaces/dots.
    publisher=$(grep -m1 '^publisher:' "$src" 2>/dev/null | sed 's/^publisher:[[:space:]]*//' || true)
    [[ -n "$publisher" ]] || UNFILED=$((UNFILED + 1))
    pub=$(bash "$HELPERS/normalize-publisher.sh" "${publisher:-unknown}" "$STACK/sources")
    dest="$STACK/sources/$pub"; mkdir -p "$dest"
    mv "$src" "$dest/"
    bash "$HELPERS/rewrite-source-refs.sh" "$STACK/articles" "$fn" "$pub"
  done < <(cut -f2 "$DEV/dispatch-w1.tsv")

  # W4: regenerate the Map of Contents (preserves the ## Reading Paths section).
  bash "$HELPERS/regenerate-moc.sh" "$STACK"

  # Cleanup: transient W1/W2 working + run-state files. articles/, sources/, and
  # index.md are the durable artifacts the skill commits.
  rm -f "$DEV"/batch-*-concepts.md "$DEV"/_dedup*.md "$DEV"/_dedup-meta.txt \
        "$DEV/dispatch-w1.tsv" "$DEV/dispatch-w2.tsv" "$DEV/run.env"

  echo "CATALOG_SUMMARY: sources=$N_SOURCES new=$N_NEW updated=$N_UPDATED unfiled=$UNFILED"
  [[ "$UNFILED" -eq 0 ]] || echo "Note: $UNFILED source(s) had no publisher field — filed under sources/unknown/; re-file if needed."
}

# --- self-check -------------------------------------------------------------
# Red-when-broken: seed a throwaway library, drive the full pipeline with
# fabricated agent output at each dispatch boundary, and assert each gate fails
# by path when its expected file is missing. Covers: prep manifest + paren gate +
# noop, gate-w1 clean/dropped, dedup manifest, gate-w2 clean/dropped, finish
# filing + MoC + cleanup, and the tag-drift halt leaving sources in incoming/.
self_check() {
  local d; d=$(mktemp -d)
  trap 'rm -rf "$d"' RETURN
  local pass=0 fail=0
  ok()  { echo "SELF-CHECK PASS [$1]"; pass=$((pass+1)); }
  bad() { echo "SELF-CHECK FAIL [$1]: $2" >&2; fail=$((fail+1)); }

  touch "$d/catalog.md"
  local ST="$d/mep"
  mkdir -p "$ST/articles" "$ST/sources/incoming"
  cat > "$ST/STACK.md" <<'EOF'
# MEP

allowed_tags:
  - hvac
  - controls
EOF
  # Two text sources (pass through convert), one carrying a publisher field.
  printf 'publisher: ashrae\n\nVAV boxes modulate airflow to meet zone load.\n' > "$ST/sources/incoming/vav-basics.md"
  printf 'Economizers use outside air for free cooling below a setpoint.\n'      > "$ST/sources/incoming/economizer.md"

  export STACKS_CONFIG="$d/config.json"
  printf '{"library":"%s"}\n' "$d" > "$d/config.json"

  local DEV="$ST/dev/extractions"

  # --- prep -----------------------------------------------------------------
  bash "$0" prep mep >/dev/null 2>&1 || bad "prep-runs" "prep exited nonzero"
  if [[ -f "$DEV/dispatch-w1.tsv" && -f "$DEV/run.env" ]] \
     && [[ "$(wc -l < "$DEV/dispatch-w1.tsv" | tr -d ' ')" == "2" ]] \
     && grep -qE '^1\t.*economizer\.md$' "$DEV/dispatch-w1.tsv"; then
    ok "prep-writes-w1-manifest"
  else
    bad "prep-writes-w1-manifest" "manifest: $(cat "$DEV/dispatch-w1.tsv" 2>/dev/null)"
  fi
  local RUN_ID_W1; RUN_ID_W1=$(grep -m1 '^RUN_ID_W1=' "$DEV/run.env" | cut -d= -f2)
  [[ "$RUN_ID_W1" =~ ^[0-9]+$ ]] && ok "prep-run-env-has-runid" || bad "prep-run-env-has-runid" "no RUN_ID_W1"

  # paren gate: a '(' filename fails prep.
  local out rc
  touch "$ST/sources/incoming/bad(name).md"
  out=$(bash "$0" prep mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -q 'bad(name)' <<<"$out"; then ok "prep-paren-gate"; else bad "prep-paren-gate" "rc=$rc out=$out"; fi
  rm -f "$ST/sources/incoming/bad(name).md"
  bash "$0" prep mep >/dev/null 2>&1   # restore a clean 2-source manifest
  RUN_ID_W1=$(grep -m1 '^RUN_ID_W1=' "$DEV/run.env" | cut -d= -f2)

  # noop: empty incoming/ → CATALOG_NOOP, exit 0.
  local d2; d2=$(mktemp -d); touch "$d2/catalog.md"; mkdir -p "$d2/empty/sources/incoming"; echo "# E" > "$d2/empty/STACK.md"
  out=$(STACKS_CONFIG="$d2/config.json"; printf '{"library":"%s"}\n' "$d2" > "$d2/config.json"; STACKS_CONFIG="$d2/config.json" bash "$0" prep empty 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]] && grep -q 'CATALOG_NOOP' <<<"$out"; then ok "prep-noop-empty-incoming"; else bad "prep-noop-empty-incoming" "rc=$rc out=$out"; fi
  rm -rf "$d2"

  # --- W1 dispatch (fabricate concept batch files) --------------------------
  mk_w1() {
    cat > "$DEV/batch-1-concepts.md" <<'EOF'
## Concept: VAV Airflow Modulation

slug: vav-airflow
title: VAV Airflow Modulation
source_paths:
  - sources/incoming/vav-basics.md
target_article: ""
tier: 2

### Claims

- VAV boxes modulate airflow to meet zone load. [source: vav-basics]
EOF
    cat > "$DEV/batch-2-concepts.md" <<'EOF'
## Concept: Airside Economizer

slug: airside-economizer
title: Airside Economizer
source_paths:
  - sources/incoming/economizer.md
target_article: ""
tier: 2

### Claims

- Economizers use outside air for free cooling below a setpoint. [source: economizer]
EOF
  }
  mk_w1
  if bash "$0" gate-w1 mep >/dev/null 2>&1; then ok "gate-w1-clean-passes"; else bad "gate-w1-clean-passes" "clean gate-w1 failed"; fi

  # gate-w1 fails BY PATH when a source's concept file is missing.
  mk_w1; rm -f "$DEV/batch-2-concepts.md"
  out=$(bash "$0" gate-w1 mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -q 'batch-2-concepts.md' <<<"$out"; then ok "gate-w1-fails-on-missing-file"; else bad "gate-w1-fails-on-missing-file" "rc=$rc out=$out"; fi
  mk_w1

  # A pure-reference source (#93) writes a receipted-empty sentinel instead of a
  # concept block. gate-w1 PASSES it (the file is present + well-formed = covered),
  # and dedup legitimately drops that source's slug from W2 — covered-with-reason,
  # not a silent drop. A reason-less sentinel must still FAIL the gate.
  mk_w1
  printf '# no-concepts: pure CLI flag reference, no behavior knowledge\n' > "$DEV/batch-2-concepts.md"
  if bash "$0" gate-w1 mep >/dev/null 2>&1; then ok "gate-w1-passes-no-concepts-sentinel"; else bad "gate-w1-passes-no-concepts-sentinel" "sentinel batch failed gate-w1"; fi
  # reason-less sentinel is rejected (conservative default — empty is usually a real failure).
  mk_w1; printf '# no-concepts:\n' > "$DEV/batch-2-concepts.md"
  out=$(bash "$0" gate-w1 mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -q 'batch-2-concepts.md' <<<"$out"; then ok "gate-w1-fails-reasonless-sentinel"; else bad "gate-w1-fails-reasonless-sentinel" "rc=$rc out=$out"; fi
  # dedup after a valid sentinel: the pure-ref source contributes no slug, the other still does.
  mk_w1; printf '# no-concepts: pure CLI flag reference, no behavior knowledge\n' > "$DEV/batch-2-concepts.md"
  bash "$0" dedup mep >/dev/null 2>&1 || bad "dedup-after-sentinel-runs" "dedup nonzero after sentinel"
  if grep -qE '^0\tvav-airflow$' "$DEV/dispatch-w2.tsv" && ! grep -q 'airside-economizer' "$DEV/dispatch-w2.tsv"; then
    ok "dedup-drops-sentinel-source-slug"
  else
    bad "dedup-drops-sentinel-source-slug" "w2: $(cat "$DEV/dispatch-w2.tsv" 2>/dev/null)"
  fi
  mk_w1

  # dedup rejects a batch file NOT in the W1 manifest — gate-w1 ignores it, so it
  # would otherwise leak its slugs into W2 via dedup-extractions.py's glob.
  printf '## Concept: Rogue\n\nslug: rogue-slug\ntitle: Rogue\nsource_paths:\n  - sources/incoming/x.md\ntarget_article: ""\ntier: 4\n\n### Claims\n- rogue.\n' > "$DEV/batch-999-concepts.md"
  out=$(bash "$0" dedup mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -q 'batch-999' <<<"$out"; then ok "dedup-rejects-unexpected-batch"; else bad "dedup-rejects-unexpected-batch" "rc=$rc out=$out"; fi
  rm -f "$DEV/batch-999-concepts.md"

  # --- dedup ----------------------------------------------------------------
  bash "$0" dedup mep >/dev/null 2>&1 || bad "dedup-runs" "dedup exited nonzero"
  if [[ -f "$DEV/dispatch-w2.tsv" ]] \
     && grep -qE '^0\tairside-economizer$' "$DEV/dispatch-w2.tsv" \
     && grep -qE '^0\tvav-airflow$' "$DEV/dispatch-w2.tsv"; then
    ok "dedup-writes-w2-manifest"
  else
    bad "dedup-writes-w2-manifest" "w2: $(cat "$DEV/dispatch-w2.tsv" 2>/dev/null)"
  fi
  local RUN_ID_W2; RUN_ID_W2=$(grep -m1 '^RUN_ID_W2=' "$DEV/run.env" | cut -d= -f2)
  [[ "$RUN_ID_W2" =~ ^[0-9]+$ ]] && ok "dedup-run-env-has-runid" || bad "dedup-run-env-has-runid" "no RUN_ID_W2"

  # --- W2 dispatch (fabricate articles) -------------------------------------
  mk_w2() {
    cat > "$ST/articles/vav-airflow.md" <<'EOF'
---
title: VAV Airflow Modulation
last_verified: ""
tags: [hvac]
---
VAV boxes modulate airflow to meet zone load.
EOF
    cat > "$ST/articles/airside-economizer.md" <<'EOF'
---
title: Airside Economizer
last_verified: ""
tags: [controls]
---
Economizers use outside air for free cooling below a setpoint.
EOF
  }
  mk_w2
  if bash "$0" gate-w2 mep >/dev/null 2>&1; then ok "gate-w2-clean-passes"; else bad "gate-w2-clean-passes" "clean gate-w2 failed"; fi

  # gate-w2 fails BY PATH when a slug's article is missing.
  mk_w2; rm -f "$ST/articles/airside-economizer.md"
  out=$(bash "$0" gate-w2 mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -q 'airside-economizer.md' <<<"$out"; then ok "gate-w2-fails-on-missing-article"; else bad "gate-w2-fails-on-missing-article" "rc=$rc out=$out"; fi
  mk_w2

  # --- finish scenarios ------------------------------------------------------
  # finish is destructive (moves sources, clears run-state), so snapshot the clean
  # pre-finish state (incoming + run-state + articles) and restore before each case.
  local SNAP="$d/_snap"
  mkdir -p "$SNAP"
  cp -R "$ST/sources/incoming" "$SNAP/incoming"
  cp -R "$DEV" "$SNAP/extractions"
  cp -R "$ST/articles" "$SNAP/articles"
  reset_prefinish() {
    rm -rf "$ST/sources/incoming" "$DEV" "$ST/articles" "$ST/index.md"
    find "$ST/sources" -mindepth 1 -maxdepth 1 -type d ! -name incoming -exec rm -rf {} +
    cp -R "$SNAP/incoming" "$ST/sources/incoming"
    cp -R "$SNAP/extractions" "$DEV"
    cp -R "$SNAP/articles" "$ST/articles"
  }

  # Tag drift → finish HALTS before filing; sources stay in incoming/.
  reset_prefinish
  awk '{gsub(/tags: \[hvac\]/,"tags: [not-a-real-tag]")}1' "$SNAP/articles/vav-airflow.md" > "$ST/articles/vav-airflow.md"
  out=$(bash "$0" finish mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && [[ -f "$ST/sources/incoming/vav-basics.md" ]]; then ok "finish-halts-on-tag-drift"; else bad "finish-halts-on-tag-drift" "rc=$rc incoming=$([[ -f "$ST/sources/incoming/vav-basics.md" ]] && echo y || echo N)"; fi

  # A dispatched slug with no article → finish FAILS by name (does not trust that
  # gate-w2 ran) and does NOT move sources out of incoming/.
  reset_prefinish; rm -f "$ST/articles/airside-economizer.md"
  out=$(bash "$0" finish mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -q 'airside-economizer' <<<"$out" && [[ -f "$ST/sources/incoming/vav-basics.md" ]]; then ok "finish-fails-on-missing-article"; else bad "finish-fails-on-missing-article" "rc=$rc out=$out"; fi

  # finish without a W2 manifest (prep->finish, no dedup) fails cleanly, not a
  # cryptic pipefail crash; sources untouched.
  reset_prefinish; rm -f "$DEV/dispatch-w2.tsv"
  out=$(bash "$0" finish mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -q 'dispatch-w2' <<<"$out" && [[ -f "$ST/sources/incoming/vav-basics.md" ]]; then ok "finish-requires-dedup"; else bad "finish-requires-dedup" "rc=$rc out=$out"; fi

  # A source dropped into incoming/ AFTER prep is NOT filed (not in the manifest) —
  # it must stay queued, not be moved out uncataloged.
  reset_prefinish; printf 'late drop\n' > "$ST/sources/incoming/late.md"
  out=$(bash "$0" finish mep 2>&1) || bad "finish-extra-runs" "finish nonzero: $out"
  if [[ -f "$ST/sources/incoming/late.md" ]] && [[ ! -f "$ST/sources/incoming/vav-basics.md" ]] && grep -q 'sources=2' <<<"$out"; then ok "finish-ignores-post-prep-drop"; else bad "finish-ignores-post-prep-drop" "late=$([[ -f "$ST/sources/incoming/late.md" ]] && echo y || echo N) out=$out"; fi

  # Counts recompute from the LIVE manifest: an operator near-dup merge drops a W2
  # row + its article, so new must fall to 1 (a stale run.env count would say 2).
  reset_prefinish
  grep -v $'\tairside-economizer$' "$DEV/dispatch-w2.tsv" > "$DEV/dispatch-w2.tsv.tmp" && mv "$DEV/dispatch-w2.tsv.tmp" "$DEV/dispatch-w2.tsv"
  rm -f "$ST/articles/airside-economizer.md"
  out=$(bash "$0" finish mep 2>&1) || bad "finish-merge-runs" "$out"
  grep -q 'sources=2 new=1 updated=0' <<<"$out" && ok "finish-recomputes-counts" || bad "finish-recomputes-counts" "out=$out"

  # A multi-word publisher files under the FULL normalized dir (awk '{print $2}'
  # truncated "U.S. Department of Energy" to "u-s").
  reset_prefinish; printf 'publisher: U.S. Department of Energy\n\nbody\n' > "$ST/sources/incoming/vav-basics.md"
  out=$(bash "$0" finish mep 2>&1) || bad "finish-pub-runs" "$out"
  [[ -f "$ST/sources/u-s-department-of-energy/vav-basics.md" ]] && ok "finish-full-publisher" || bad "finish-full-publisher" "sources dirs: $(ls "$ST/sources")"

  # Clean run: file both dispatched sources, regenerate MoC, cleanup, correct counts.
  reset_prefinish
  out=$(bash "$0" finish mep 2>&1) || bad "finish-runs" "finish exited nonzero"
  if grep -q 'sources=2 new=2 updated=0' <<<"$out" \
     && [[ -f "$ST/sources/ashrae/vav-basics.md" ]] \
     && [[ -f "$ST/sources/unknown/economizer.md" ]] \
     && [[ ! -f "$ST/sources/incoming/vav-basics.md" ]] \
     && [[ -f "$ST/index.md" ]]; then
    ok "finish-files-sources-and-moc"
  else
    bad "finish-files-sources-and-moc" "out=$out; ashrae=$([[ -f "$ST/sources/ashrae/vav-basics.md" ]] && echo y || echo N) unknown=$([[ -f "$ST/sources/unknown/economizer.md" ]] && echo y || echo N) moc=$([[ -f "$ST/index.md" ]] && echo y || echo N)"
  fi
  grep -q 'unfiled=1' <<<"$out" && ok "finish-reports-unfiled" || bad "finish-reports-unfiled" "out=$out"
  [[ ! -f "$DEV/run.env" && ! -f "$DEV/dispatch-w2.tsv" ]] && ok "finish-cleans-run-state" || bad "finish-cleans-run-state" "run-state survived"

  echo "---"; echo "self-check: $pass passed, $fail failed"
  [[ "$fail" -eq 0 ]]
}

# --- dispatch ---------------------------------------------------------------
cmd="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$cmd" in
  queue)        phase_queue ;;
  prep)         phase_prep "$@" ;;
  gate-w1)      phase_gate_w1 "$@" ;;
  dedup)        phase_dedup "$@" ;;
  gate-w2)      phase_gate_w2 "$@" ;;
  finish)       phase_finish "$@" ;;
  --self-check) self_check ;;
  *) echo "usage: catalog.sh {queue|prep|gate-w1|dedup|gate-w2|finish} <stack> [--from P]  |  catalog.sh --self-check" >&2; exit 1 ;;
esac
