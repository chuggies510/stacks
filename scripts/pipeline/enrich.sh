#!/usr/bin/env bash
set -euo pipefail

# Enrich-stack pipeline orchestration — the deterministic control flow that used
# to live in enrich-stack SKILL.md Bash blocks, now one checked-in script with
# phase subcommands. The model dispatch (enrichment agents) and the operator
# approval + WebFetch staging stay in the skill as prose; everything mechanical
# (arg parse, gap assembly, sharding, gating, URL dedup, cleanup) is here.
#
# Usage:
#   bash enrich.sh prep   <stack> [--auto] [--query <text>]   # Steps 1-3
#   bash enrich.sh gate   <stack>                             # Step 4 gate
#   bash enrich.sh finish <stack>                             # Step 5 dedup + cleanup
#   bash enrich.sh --self-check
#
# Phase contract (why subcommands: a bash script can't spawn subagents, so the
# pipeline is always prep -> model dispatch -> gate -> finish, split at the
# dispatch boundary):
#
#   prep    Resolve the library, parse args, build the filed-sources listing,
#           assemble gaps (audit soft-spots stale-checked + telemetry misses, OR
#           the single --query gap), shard into CAP=5 batches, and write the two
#           run-state files below plus clear stale per-batch findings. Prints the
#           paths + a per-batch summary the dispatch prose reads. Exits 0 with a
#           "nothing to enrich" line when no live gaps.
#   gate    Re-read run-state from disk, gate every expected _enrich-<tag>.md
#           (gate-batch.sh: write-or-fail + enrichment-findings shape) then
#           check-coverage.sh --field 2 (reconciles dispatched gap_ids vs the
#           gap_id column of the findings rows). A dropped/dup/unknown/missing
#           findings row fails by name.
#   finish  Aggregate the per-batch findings, dedup CANDIDATE/WEAK rows by url
#           (never NOSOURCE — empty url), print the consolidated rows for the
#           operator table + staging, then remove the transient run files. The
#           deduped view is consumed from the model's context by the interactive
#           approval (Step 6) and staging (Step 7); nothing on disk is needed
#           after this, so a later operator cancel leaves the correct end state.
#
# State crosses phases ONLY through these files, never shell env (the #72 fix —
# a var set in one SKILL.md Bash block is empty in the next):
#
#   dev/enrich/run.env       KEY=VAL. RUN_ID (the dispatch epoch, also the
#                            gate-batch freshness floor), STACK, AUTO, QUERY,
#                            gap counts, CAP, and the DISPATCH/LISTING paths.
#                            Read by grep (not sourced) so a query with quotes
#                            can't break parsing.
#   dev/enrich/dispatch.tsv  The coverage manifest, one row per gap:
#                            batch_tag<TAB>gap_id<TAB>slug<TAB>claim<TAB>reason
#                            col 1 groups gaps into one agent's assignment; col 2
#                            (gap_id) is what check-coverage reconciles; cols 3-5
#                            are the agent's input row (gap_id..reason = cols 2-5).
#   dev/enrich/_filed-sources.tsv  slug<TAB>url of already-filed sources (dedup).
#
# gap_id scheme: gap-N, a per-run sequential index assigned in deterministic
# order (surviving soft-spots in soft-spots.tsv order, then telemetry misses;
# gap-0 for a --query run). Stable within the run, which is all coverage needs —
# it reconciles one run's dispatch against that run's receipts, nothing carries
# across runs. Matches the enrichment agent's documented gap_id echo (gap-7 etc).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPERS="$SCRIPT_DIR/.."   # scripts/ — where the shared helpers live

CAP=5   # web-search-heavy agent sweet spot per issue #76 (see enrich-stack SKILL.md Step 4)

die() { echo "ERROR: $*" >&2; exit 1; }

# Echo the resolved library's absolute path (resolve-library.sh), or fail non-zero.
# Every phase cds itself so it works with $STACK-relative paths regardless of the
# caller's cwd (self-contained — never assumes an earlier phase's cd survived).
# Callers MUST capture-then-cd with explicit failure handling:
#     local LIB; LIB=$(enter_library) || die ...; cd "$LIB" || die ...
# NEVER `cd "$(enter_library)"` — on a resolve failure that is `cd ""`, which
# SUCCEEDS as a no-op (the #74 cd-empty-string footgun) and silently runs the
# phase in the wrong directory.
enter_library() {
  bash "$HELPERS/resolve-library.sh"
}

# --- prep -------------------------------------------------------------------
phase_prep() {
  local STACK="" AUTO=0 QUERY=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --auto)  AUTO=1; shift ;;
      --query) shift; QUERY="$*"; break ;;   # --query consumes the rest (may be multi-word)
      *)       [[ -z "$STACK" ]] && STACK="$1"; shift ;;
    esac
  done
  [[ -n "$STACK" ]] || die "Specify a stack name. Usage: enrich.sh prep <stack> [--auto] [--query <text>]"

  local LIB; LIB=$(enter_library) || die "could not resolve the library (no config, and cwd is not a library)."
  cd "$LIB" || die "could not cd into library: $LIB"
  [[ -f "$STACK/STACK.md" ]] || die "Stack '$STACK' not found (no STACK.md)."

  local DEV="$STACK/dev/enrich"
  local ADEV="$LIB/$DEV"
  mkdir -p "$DEV"

  local TSV="$STACK/dev/audit/soft-spots.tsv"
  local LISTING="$DEV/_filed-sources.tsv"
  local DISPATCH="$DEV/dispatch.tsv"
  local GAPS="$DEV/_gaps.tsv"   # gap_id<TAB>slug<TAB>claim<TAB>reason, before sharding

  # Filed-sources listing (slug<TAB>url) the agents dedup against.
  : > "$LISTING"
  while IFS= read -r f; do
    local url
    # `|| true`: a source with no URL makes grep exit 1 → pipefail + set -e would
    # kill prep on the first URL-less filed source. Absent URL is normal, not fatal.
    url=$(grep -m1 -oiE '(\*\*Source:\*\*|source_url:)[[:space:]]*https?://[^[:space:]]+' "$f" 2>/dev/null \
          | grep -oE 'https?://[^[:space:]]+' | head -1 || true)
    [[ -n "$url" ]] && printf '%s\t%s\n' "$(basename "$f" .md)" "$url" >> "$LISTING"
  done < <(find "$STACK/sources" -type f -name '*.md' \
             ! -path '*/incoming/*' ! -path '*/trash/*' ! -path '*/.raw/*' 2>/dev/null)

  # Assemble gaps into $GAPS (gap_id<TAB>slug<TAB>claim<TAB>reason).
  : > "$GAPS"
  local N_SOFT=0 STALE=0 TOTAL=0 MISS=0 N_GAPS=0

  if [[ -n "$QUERY" ]]; then
    # Targeted mode (--query, lookup's live auto-path #69): exactly ONE gap, the
    # query that just missed. No soft-spot scan, no telemetry mining — one user
    # lookup authorizes researching that query only, not the whole backlog.
    local q_flat; q_flat=$(printf '%s' "$QUERY" | tr -s '[:space:]' ' ')
    printf 'gap-0\tlookup-miss\t%s\tlookup miss\n' "$q_flat" >> "$GAPS"
    N_GAPS=1
  else
    # Batch mode: audit soft spots (stale-checked) + mined lookup misses.
    local i=0
    if [[ -f "$TSV" ]]; then
      while IFS=$'\t' read -r slug claim reason; do
        [[ -z "$slug" ]] && continue
        TOTAL=$((TOTAL+1))
        local art="$STACK/articles/$slug.md"
        # The validator collapsed the claim's whitespace to single spaces; the
        # article body keeps its original line breaks, so flatten the article the
        # same way before matching or a wrapped claim never grep -Fq matches.
        if [[ ! -f "$art" ]] || ! tr -s '[:space:]' ' ' < "$art" | grep -Fq "$claim"; then
          STALE=$((STALE+1)); continue
        fi
        printf 'gap-%s\t%s\t%s\t%s\n' "$i" "$slug" "$claim" "$reason" >> "$GAPS"
        i=$((i+1))
      done < "$TSV"
    fi
    N_SOFT=$i
    # Lookup misses (#68): live queries the stack could not answer. Sentinel slug
    # lookup-miss (no home article, so they skip the stale-check above).
    while IFS=$'\t' read -r slug claim reason; do
      [[ -z "$claim" ]] && continue
      printf 'gap-%s\t%s\t%s\t%s\n' "$i" "$slug" "$claim" "$reason" >> "$GAPS"
      i=$((i+1)); MISS=$((MISS+1))
    done < <(bash "$HELPERS/lookup-misses.sh" "$STACK")
    N_GAPS=$i
  fi

  if [[ "$N_GAPS" -eq 0 ]]; then
    rm -f "$GAPS"
    echo "No live gaps — soft spots all stale/absent and no lookup misses. Nothing to enrich."
    return 0
  fi

  # Shard into CAP-sized batches and write the dispatch manifest (prepend the
  # batch_tag to each gap row). Then drop $GAPS — dispatch.tsv supersedes it.
  awk -F'\t' -v cap="$CAP" 'NF>=1 { printf "%d\t%s\n", int((NR-1)/cap), $0 }' "$GAPS" > "$DISPATCH"
  rm -f "$GAPS"

  # Clear any stale per-batch findings from a prior run (freshness gate depends
  # on this: every kept file must be written strictly after RUN_ID below).
  rm -f "$DEV"/_enrich-*.md

  local RUN_ID; RUN_ID=$(date +%s)
  local N_BATCH; N_BATCH=$(cut -f1 "$DISPATCH" | sort -u | wc -l | tr -d ' ')
  {
    echo "RUN_ID=$RUN_ID"
    echo "STACK=$STACK"
    echo "AUTO=$AUTO"
    echo "QUERY=$QUERY"
    echo "N_GAPS=$N_GAPS"
    echo "N_SOFT=$N_SOFT"
    echo "N_STALE=$STALE"
    echo "N_MISS=$MISS"
    echo "CAP=$CAP"
    echo "DISPATCH=$ADEV/dispatch.tsv"
    echo "LISTING=$ADEV/_filed-sources.tsv"
  } > "$DEV/run.env"

  if [[ -n "$QUERY" ]]; then
    echo "Targeted enrich: 1 gap (the lookup miss \"$QUERY\"). AUTO=$AUTO"
  else
    echo "Soft spots: $TOTAL total, $STALE stale, $N_SOFT live; lookup misses: $MISS; $N_GAPS gaps to enrich. AUTO=$AUTO"
  fi
  echo "Filed-sources listing: $(wc -l < "$LISTING" | tr -d ' ') sources with URLs (for dedup)."
  echo "Dispatch: $N_BATCH batch(es), CAP=$CAP, RUN_ID=$RUN_ID"
  echo "Manifest:  $ADEV/dispatch.tsv   (batch_tag<TAB>gap_id<TAB>slug<TAB>claim<TAB>reason)"
  echo "Listing:   $ADEV/_filed-sources.tsv"
  echo "Stack root: $LIB/$STACK"
  echo "Dispatch one stacks:enrichment agent per distinct batch_tag; write findings to $LIB/$DEV/_enrich-<batch_tag>.md"
}

# --- gate -------------------------------------------------------------------
phase_gate() {
  local STACK="${1:-}"; [[ -n "$STACK" ]] || die "Usage: enrich.sh gate <stack>"
  local LIB; LIB=$(enter_library) || die "could not resolve the library."
  cd "$LIB" || die "could not cd into library: $LIB"
  local DEV="$STACK/dev/enrich"
  [[ -f "$DEV/run.env" ]]      || die "no run.env at $DEV — run 'enrich.sh prep' first."
  [[ -f "$DEV/dispatch.tsv" ]] || die "no dispatch.tsv at $DEV — run 'enrich.sh prep' first."

  local RUN_ID; RUN_ID=$(grep -m1 '^RUN_ID=' "$DEV/run.env" | cut -d= -f2)
  [[ "$RUN_ID" =~ ^[0-9]+$ ]] || die "RUN_ID missing/garbled in $DEV/run.env"

  # Expected per-batch files, one per distinct batch_tag in the manifest.
  local BATCHFILES=() t
  while IFS= read -r t; do BATCHFILES+=("$DEV/_enrich-$t.md"); done < <(cut -f1 "$DEV/dispatch.tsv" | sort -u)

  # 1) write-or-fail + structure. 2) per-gap coverage (gap_id is col 2 of both
  # the manifest and every findings row).
  bash "$HELPERS/gate-batch.sh" "$RUN_ID" enrichment enrichment-findings "${BATCHFILES[@]}"
  bash "$HELPERS/check-coverage.sh" --field 2 "$DEV/dispatch.tsv" "${BATCHFILES[@]}"
}

# --- finish -----------------------------------------------------------------
phase_finish() {
  local STACK="${1:-}"; [[ -n "$STACK" ]] || die "Usage: enrich.sh finish <stack>"
  local LIB; LIB=$(enter_library) || die "could not resolve the library."
  cd "$LIB" || die "could not cd into library: $LIB"
  local DEV="$STACK/dev/enrich"

  # Consolidate findings: pass DUP/NOSOURCE through, dedup CANDIDATE/WEAK by url
  # (never NOSOURCE — its url is empty and would collapse into one bogus group),
  # merging the gap_ids/slugs a single url serves. Output shape (8 tab fields):
  #   KIND<TAB>gap_ids<TAB>slugs<TAB>source_ref<TAB>url<TAB>tier<TAB>title<TAB>quote
  shopt -s nullglob
  local FILES=("$DEV"/_enrich-*.md)
  shopt -u nullglob
  if [[ ${#FILES[@]} -gt 0 ]]; then
    awk -F'\t' '
      $0=="" { next }
      {
        kind=$1; gid=$2; slug=$3; sref=$4; url=$5; tier=$6; title=$7; quote=$8
        if (kind=="NOSOURCE" || kind=="DUP") { print; next }
        if ((kind=="CANDIDATE" || kind=="WEAK") && url!="") {
          key=kind SUBSEP url
          if (!(key in seen)) {
            seen[key]=1; order[++n]=key
            k_kind[key]=kind; k_sref[key]=sref; k_url[key]=url
            k_tier[key]=tier; k_title[key]=title; k_quote[key]=quote
            k_gids[key]=gid; k_slugs[key]=slug
          } else {
            k_gids[key]=k_gids[key] "," gid
            if (index("," k_slugs[key] ",", "," slug ",")==0) k_slugs[key]=k_slugs[key] "," slug
          }
          next
        }
        print   # CANDIDATE/WEAK with empty url (unexpected) — pass through
      }
      END {
        for (i=1;i<=n;i++) { key=order[i]
          printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
            k_kind[key], k_gids[key], k_slugs[key], k_sref[key],
            k_url[key], k_tier[key], k_title[key], k_quote[key]
        }
      }
    ' "${FILES[@]}"
  fi

  # Cleanup: the deduped view above is now in the model's context; nothing on
  # disk is needed for approval/staging. Removing here means an operator cancel
  # (Step 6) leaves the correct clean end state with no extra step.
  rm -f "$DEV"/_enrich-*.md "$DEV/dispatch.tsv" "$DEV/run.env" "$DEV/_filed-sources.tsv" "$DEV/_gaps.tsv"
}

# --- self-check -------------------------------------------------------------
# Red-when-broken: seed a throwaway library, run prep, assert the manifest +
# run.env shape, run gate clean (fabricated findings) -> PASS, then drop one
# findings file and assert gate FAILS naming that batch's gap_id.
self_check() {
  local d; d=$(mktemp -d)
  trap 'rm -rf "$d"' RETURN
  local pass=0 fail=0
  ok()   { echo "SELF-CHECK PASS [$1]"; pass=$((pass+1)); }
  bad()  { echo "SELF-CHECK FAIL [$1]: $2" >&2; fail=$((fail+1)); }

  # Minimal library: catalog.md at root + a stack with STACK.md, two articles
  # whose claims occur verbatim (survive the stale-check → gap-0, gap-1 in one
  # batch) plus one claim that does NOT (dropped as stale).
  touch "$d/catalog.md"
  mkdir -p "$d/mep/articles" "$d/mep/sources/ashrae" "$d/mep/dev/audit"
  echo "# MEP" > "$d/mep/STACK.md"
  # A filed source with NO URL: exercises the listing-loop grep-no-match path so a
  # missing `|| true` (which killed prep under set -e + pipefail) fails prep-runs.
  printf '# ASHRAE notes\n\nNo source url in this file.\n' > "$d/mep/sources/ashrae/notes.md"
  printf '# VAV\n\nMinimum VAV box airflow is typically 20%% of design maximum.\n' > "$d/mep/articles/vav.md"
  printf '# Chiller\n\nChilled water is commonly distributed at 44 F supply.\n'    > "$d/mep/articles/chiller.md"
  {
    printf 'vav\tMinimum VAV box airflow is typically 20%% of design maximum.\tno cited source\n'
    printf 'chiller\tChilled water is commonly distributed at 44 F supply.\tno cited source\n'
    printf 'vav\tThis claim was deleted from the article since the audit.\tstale test\n'
  } > "$d/mep/dev/audit/soft-spots.tsv"

  export STACKS_CONFIG="$d/config.json"
  printf '{"library":"%s"}\n' "$d" > "$d/config.json"

  # prep
  bash "$0" prep mep >/dev/null 2>&1 || { bad "prep-runs" "prep exited nonzero"; }
  local DISP="$d/mep/dev/enrich/dispatch.tsv" ENV="$d/mep/dev/enrich/run.env"
  [[ -f "$DISP" && -f "$ENV" ]] && ok "prep-writes-run-state" || bad "prep-writes-run-state" "missing dispatch.tsv/run.env"
  # Two live gaps (the stale row dropped); gap-0 + gap-1, both batch 0.
  if [[ "$(wc -l < "$DISP" | tr -d ' ')" == "2" ]] && grep -q $'^0\tgap-0\tvav\t' "$DISP" && grep -q $'^0\tgap-1\tchiller\t' "$DISP"; then
    ok "prep-drops-stale-gap"
  else
    bad "prep-drops-stale-gap" "expected gap-0(vav)+gap-1(chiller), got: $(cat "$DISP")"
  fi
  grep -q '^RUN_ID=[0-9]' "$ENV" && ok "run-env-has-runid" || bad "run-env-has-runid" "no RUN_ID"

  local F0="$d/mep/dev/enrich/_enrich-0.md"
  mk_clean() {
    printf 'CANDIDATE\tgap-0\tvav\t\thttps://example.org/vav\t2\tASHRAE VAV\tminimum box airflow is 20%% of design max\nNOSOURCE\tgap-1\tchiller\t\t\t\t\tno source found for 44 F supply\n' > "$F0"
  }
  mk_clean
  if bash "$0" gate mep >/dev/null 2>&1; then ok "gate-clean-passes"; else bad "gate-clean-passes" "clean gate failed"; fi

  # Present-but-incomplete file: drop the gap-1 row → gate-batch passes (file
  # present + well-formed), check-coverage FAILS naming the missing gap-1.
  local out rc
  printf 'CANDIDATE\tgap-0\tvav\t\thttps://example.org/vav\t2\tASHRAE VAV\tminimum box airflow is 20%% of design max\n' > "$F0"
  out=$(bash "$0" gate mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qw 'gap-1' <<<"$out"; then
    ok "gate-fails-naming-dropped-row"
  else
    bad "gate-fails-naming-dropped-row" "expected nonzero + 'gap-1', rc=$rc out=$out"
  fi

  # Whole findings file deleted → gate-batch trips first, failing by path.
  mk_clean; rm -f "$F0"
  out=$(bash "$0" gate mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -q '_enrich-0.md' <<<"$out"; then
    ok "gate-fails-on-deleted-file"
  else
    bad "gate-fails-on-deleted-file" "expected nonzero + path, rc=$rc out=$out"
  fi

  echo "---"; echo "self-check: $pass passed, $fail failed"
  [[ "$fail" -eq 0 ]]
}

# --- dispatch ---------------------------------------------------------------
cmd="${1:-}"; [[ $# -gt 0 ]] && shift || true
case "$cmd" in
  prep)         phase_prep "$@" ;;
  gate)         phase_gate "$@" ;;
  finish)       phase_finish "$@" ;;
  --self-check) self_check ;;
  *) echo "usage: enrich.sh {prep|gate|finish} <stack> [...]  |  enrich.sh --self-check" >&2; exit 1 ;;
esac
