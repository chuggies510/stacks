#!/usr/bin/env bash
set -euo pipefail

# Audit-stack pipeline orchestration — the deterministic control flow that used
# to live in audit-stack SKILL.md Bash blocks, now one checked-in script with
# phase subcommands. The model dispatch (validator agents) stays in the skill as
# prose; everything mechanical (arg parse, article enum, sharding, gating, report
# aggregation, cleanup) is here. Mirrors scripts/pipeline/enrich.sh (#87).
#
# Usage:
#   bash audit.sh prep   <stack>   # Step 1+3-setup: enum, shard, run-state
#   bash audit.sh gate   <stack>   # Step 3-gate: gate-batch + check-coverage
#   bash audit.sh finish <stack>   # Step 4: report.md + soft-spots.tsv + counts
#   bash audit.sh --self-check
#
# Phase contract (subcommands because a bash script can't spawn subagents, so the
# pipeline is always prep -> validator dispatch -> gate -> finish, split at the
# dispatch boundary):
#
#   prep    Resolve the library, enum articles/*.md, shard into CAP=3 batches, and
#           write dev/audit/dispatch.tsv + run.env (with RUN_ID). Clears stale
#           per-batch findings. Prints the paths + dispatch instructions the skill
#           prose reads. Exits non-zero if the stack has no articles.
#   gate    Re-read run-state from disk, gate every expected _audit-<tag>.md
#           (gate-batch.sh: write-or-fail + audit-findings shape = a VALIDATED
#           receipt row exists) then check-coverage.sh --verdict VALIDATED --field 2
#           (reconciles dispatched slugs vs the slug column of the VALIDATED
#           receipt rows). A dropped/dup/unknown/missing receipt fails by name.
#           This replaces the old per-article `last_verified == today` date-gate,
#           which proved a date but never per-article coverage (#71 headline).
#   finish  Aggregate CORRECTION/SOFTSPOT rows across the dispatched batch files
#           (enumerated from dispatch.tsv, not globbed — a file the gate somehow
#           let through still can't silently shrink the report), write report.md +
#           soft-spots.tsv, print AUDIT_SUMMARY counts for the skill's log+commit,
#           then remove the transient run files. VALIDATED receipt rows are ignored
#           by the report (it filters CORRECTION/SOFTSPOT only).
#
# State crosses phases ONLY through these files, never shell env (the #72 fix —
# a var set in one SKILL.md Bash block is empty in the next):
#
#   dev/audit/run.env       KEY=VAL. RUN_ID (dispatch epoch + gate-batch freshness
#                           floor), STACK, N_ARTICLES, CAP, DISPATCH path.
#   dev/audit/dispatch.tsv  The coverage manifest, one row per article:
#                           batch_tag<TAB>slug<TAB>article_path
#                           col 1 groups articles into one validator's assignment;
#                           col 2 (slug) is what check-coverage reconciles; col 3
#                           is the absolute path handed to the agent.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPERS="$SCRIPT_DIR/.."   # scripts/ — where the shared helpers live

CAP=3   # articles per validator agent. Small on purpose: each agent re-reads every
        # cited source too, so a big slice risks prompt-overflow + cross-article
        # contamination. Raise only if dispatch fan-out becomes the bottleneck.

die() { echo "ERROR: $*" >&2; exit 1; }

# Echo the resolved library's absolute path, or fail non-zero. Every phase cds
# itself (self-contained — never assumes an earlier phase's cd survived). Callers
# MUST capture-then-cd, never `cd "$(enter_library)"` (on a resolve failure that
# is `cd ""`, which succeeds as a no-op and runs in the wrong dir — the #74 footgun).
enter_library() {
  bash "$HELPERS/resolve-library.sh"
}

# --- prep -------------------------------------------------------------------
phase_prep() {
  local STACK="${1:-}"
  [[ -n "$STACK" ]] || die "Specify a stack name. Usage: audit.sh prep <stack>"

  local LIB; LIB=$(enter_library) || die "could not resolve the library (no config, and cwd is not a library)."
  cd "$LIB" || die "could not cd into library: $LIB"
  [[ -f "$STACK/STACK.md" ]] || die "Stack '$STACK' not found (no STACK.md)."

  local DEV="$STACK/dev/audit"
  local ADEV="$LIB/$DEV"
  mkdir -p "$DEV"

  # Enumerate articles (sorted, stable order → deterministic batch assignment).
  local ARTICLES=() a
  while IFS= read -r a; do ARTICLES+=("$a"); done \
    < <(find "$STACK/articles" -maxdepth 1 -name '*.md' 2>/dev/null | sort)
  local N=${#ARTICLES[@]}
  [[ "$N" -ge 1 ]] || die "No articles found in $STACK/articles/. Run /stacks:catalog-sources $STACK first."

  # Dispatch manifest: batch_tag<TAB>slug<TAB>article_path, CAP articles per batch.
  local DISPATCH="$DEV/dispatch.tsv"
  : > "$DISPATCH"
  local i slug
  for i in "${!ARTICLES[@]}"; do
    slug=$(basename "${ARTICLES[$i]}" .md)
    printf '%d\t%s\t%s\n' "$((i / CAP))" "$slug" "$LIB/${ARTICLES[$i]}" >> "$DISPATCH"
  done

  # Clear stale per-batch findings (freshness gate depends on every kept file
  # being written strictly after RUN_ID below).
  rm -f "$DEV"/_audit-*.md

  local RUN_ID; RUN_ID=$(date +%s)
  local N_BATCH; N_BATCH=$(cut -f1 "$DISPATCH" | sort -u | wc -l | tr -d ' ')
  {
    echo "RUN_ID=$RUN_ID"
    echo "STACK=$STACK"
    echo "N_ARTICLES=$N"
    echo "CAP=$CAP"
    echo "DISPATCH=$ADEV/dispatch.tsv"
  } > "$DEV/run.env"

  echo "Articles: $N.  Dispatch: $N_BATCH batch(es), CAP=$CAP, RUN_ID=$RUN_ID"
  echo "Manifest:   $ADEV/dispatch.tsv   (batch_tag<TAB>slug<TAB>article_path)"
  echo "Sources:    $LIB/$STACK/sources/   (validators read cited sources; exclude incoming/ + trash/)"
  echo "Stack root: $LIB/$STACK"
  echo "Dispatch one stacks:validator agent per distinct batch_tag; pass BATCH_TAG + RUN_ID=$RUN_ID; write findings to $LIB/$DEV/_audit-<batch_tag>.md"
}

# --- gate -------------------------------------------------------------------
phase_gate() {
  local STACK="${1:-}"; [[ -n "$STACK" ]] || die "Usage: audit.sh gate <stack>"
  local LIB; LIB=$(enter_library) || die "could not resolve the library."
  cd "$LIB" || die "could not cd into library: $LIB"
  local DEV="$STACK/dev/audit"
  [[ -f "$DEV/run.env" ]]      || die "no run.env at $DEV — run 'audit.sh prep' first."
  [[ -f "$DEV/dispatch.tsv" ]] || die "no dispatch.tsv at $DEV — run 'audit.sh prep' first."

  local RUN_ID; RUN_ID=$(grep -m1 '^RUN_ID=' "$DEV/run.env" | cut -d= -f2)
  [[ "$RUN_ID" =~ ^[0-9]+$ ]] || die "RUN_ID missing/garbled in $DEV/run.env"

  # Expected per-batch files, one per distinct batch_tag in the manifest.
  local BATCHFILES=() t
  while IFS= read -r t; do BATCHFILES+=("$DEV/_audit-$t.md"); done < <(cut -f1 "$DEV/dispatch.tsv" | sort -u)

  # 1) write-or-fail + a VALIDATED receipt row exists.
  bash "$HELPERS/gate-batch.sh" "$RUN_ID" validator audit-findings "${BATCHFILES[@]}"

  # 2) every VALIDATED receipt must carry THIS run's RUN_ID in col 3. gate-batch's
  # mtime proves the FILE is fresh; this proves each ROW is — catching an agent
  # that echoed a wrong/empty RUN_ID or copied a receipt forward. Without it the
  # RUN_ID column would be pure decoration (finish deletes the file, so it is
  # never persisted). Runs after gate-batch, so every path here exists.
  local BADRUN
  BADRUN=$(awk -F'\t' -v r="$RUN_ID" '$1=="VALIDATED" && $3!=r {print $2}' "${BATCHFILES[@]}")
  if [[ -n "$BADRUN" ]]; then
    echo "AUDIT_GATE_FAILURE: VALIDATED receipt(s) not carrying RUN_ID=$RUN_ID (slug(s)): $(printf '%s' "$BADRUN" | paste -sd' ' -)" >&2
    exit 1
  fi

  # 3) per-article coverage: every dispatched slug (manifest col 2) has exactly one
  # VALIDATED receipt (col 2 of the VALIDATED-only rows; --verdict skips CORRECTION/
  # SOFTSPOT which reuse the slug column). NOTE: reconciliation is over the UNION of
  # all batch files, not per-batch — a slug dropped by its own batch but emitted by
  # another still passes (tracked as #92, shared with enrich; a misbehaving cross-
  # batch receipt is the only gap, the common drop-and-emit-nothing case is caught).
  bash "$HELPERS/check-coverage.sh" --verdict VALIDATED --field 2 "$DEV/dispatch.tsv" "${BATCHFILES[@]}"
}

# --- finish -----------------------------------------------------------------
phase_finish() {
  local STACK="${1:-}"; [[ -n "$STACK" ]] || die "Usage: audit.sh finish <stack>"
  local LIB; LIB=$(enter_library) || die "could not resolve the library."
  cd "$LIB" || die "could not cd into library: $LIB"
  local DEV="$STACK/dev/audit"
  [[ -f "$DEV/run.env" ]]      || die "no run.env at $DEV — run 'audit.sh prep' first."
  [[ -f "$DEV/dispatch.tsv" ]] || die "no dispatch.tsv at $DEV — run 'audit.sh prep' first."

  local N_ARTICLES; N_ARTICLES=$(grep -m1 '^N_ARTICLES=' "$DEV/run.env" | cut -d= -f2)

  # Aggregate from the dispatched batch files (enumerated, not globbed — a stray
  # extra _audit-*.md can't leak in, and a dispatched-but-vanished file FAILS here
  # instead of `cat 2>/dev/null` silently shrinking the report; the old skill's
  # glob+swallow is the bug this kills). The gate normally guarantees presence, but
  # finish must not trust that — it can be run standalone.
  local BATCHFILES=() t MISSING=()
  while IFS= read -r t; do
    if [[ -f "$DEV/_audit-$t.md" ]]; then BATCHFILES+=("$DEV/_audit-$t.md")
    else MISSING+=("_audit-$t.md"); fi
  done < <(cut -f1 "$DEV/dispatch.tsv" | sort -u)
  [[ ${#MISSING[@]} -eq 0 ]] || die "finish: dispatched batch file(s) missing (run gate first): ${MISSING[*]}"

  local REPORT="$DEV/report.md"
  local TODAY; TODAY=$(date +%Y-%m-%d)
  local AUDIT_LINES=""
  [[ ${#BATCHFILES[@]} -gt 0 ]] && AUDIT_LINES=$(cat "${BATCHFILES[@]}")
  local N_CORR N_SOFT
  N_CORR=$(printf '%s\n' "$AUDIT_LINES" | grep -c '^CORRECTION'$'\t' || true)
  N_SOFT=$(printf '%s\n' "$AUDIT_LINES" | grep -c '^SOFTSPOT'$'\t' || true)

  {
    echo "# $STACK — audit report ($TODAY)"
    echo
    echo "Regenerated fresh each audit. Not a persistent ledger."
    echo
    echo "Articles validated: $N_ARTICLES.  Corrections applied: $N_CORR.  Soft spots: $N_SOFT."
    echo
    echo "## Corrections applied"
    echo "_Claims the validator rewrote in place to match their cited source._"
    echo
    if [[ "$N_CORR" -gt 0 ]]; then
      printf '%s\n' "$AUDIT_LINES" | awk -F'\t' '$1=="CORRECTION"{printf "- `%s` — %s\n", $2, $3}'
    else echo "_None. No cited claim contradicted its source._"; fi
    echo
    echo "## Soft spots"
    echo "_Claims not tied to a cited source. Left in place — add a source or confirm._"
    echo
    if [[ "$N_SOFT" -gt 0 ]]; then
      printf '%s\n' "$AUDIT_LINES" | awk -F'\t' '$1=="SOFTSPOT"{printf "- `%s` — \"%s\" — %s\n", $2, $3, $4}'
    else echo "_None. Every claim ties to a cited source._"; fi
  } > "$REPORT"

  # Durable machine-readable soft-spot list — the /stacks:enrich-stack input.
  # slug<TAB>claim<TAB>reason. Written even when empty so enrich distinguishes
  # "audited, none soft" from "never audited".
  printf '%s\n' "$AUDIT_LINES" \
    | awk -F'\t' '$1=="SOFTSPOT"{print $2"\t"$3"\t"$4}' \
    > "$DEV/soft-spots.tsv"

  # Cleanup: transient per-batch inputs + run-state. report.md + soft-spots.tsv are
  # the durable artifacts the skill commits.
  rm -f "$DEV"/_audit-*.md "$DEV/dispatch.tsv" "$DEV/run.env"

  echo "AUDIT_SUMMARY: articles=$N_ARTICLES corrections=$N_CORR softspots=$N_SOFT"
  echo "Wrote $REPORT and $DEV/soft-spots.tsv ($N_SOFT soft spots)"
}

# --- self-check -------------------------------------------------------------
# Red-when-broken: seed a throwaway library with 4 articles (→ 2 batches at CAP=3),
# run prep, assert the manifest shape, fabricate clean validator output → gate PASS,
# then (a) drop one VALIDATED receipt row → gate FAILS naming that slug, (b) delete
# a whole batch file → gate FAILS by path, then finish → report counts correct.
self_check() {
  local d; d=$(mktemp -d)
  trap 'rm -rf "$d"' RETURN
  local pass=0 fail=0
  ok()  { echo "SELF-CHECK PASS [$1]"; pass=$((pass+1)); }
  bad() { echo "SELF-CHECK FAIL [$1]: $2" >&2; fail=$((fail+1)); }

  touch "$d/catalog.md"
  mkdir -p "$d/mep/articles" "$d/mep/sources" "$d/mep/dev/audit"
  echo "# MEP" > "$d/mep/STACK.md"
  local s
  for s in vav chiller pump cooling-tower; do
    printf '# %s\n\nBody.\n' "$s" > "$d/mep/articles/$s.md"
  done

  export STACKS_CONFIG="$d/config.json"
  printf '{"library":"%s"}\n' "$d" > "$d/config.json"

  # prep
  bash "$0" prep mep >/dev/null 2>&1 || bad "prep-runs" "prep exited nonzero"
  local DISP="$d/mep/dev/audit/dispatch.tsv" ENV="$d/mep/dev/audit/run.env"
  [[ -f "$DISP" && -f "$ENV" ]] && ok "prep-writes-run-state" || bad "prep-writes-run-state" "missing dispatch.tsv/run.env"
  # 4 rows, batch 0 = first 3 slugs, batch 1 = the 4th.
  if [[ "$(wc -l < "$DISP" | tr -d ' ')" == "4" ]] \
     && grep -q $'^0\tchiller\t' "$DISP" && grep -q $'^1\tvav\t' "$DISP"; then
    ok "prep-shards-cap3"
  else
    bad "prep-shards-cap3" "expected 4 rows 3+1, got: $(cat "$DISP")"
  fi
  local RUN_ID; RUN_ID=$(grep -m1 '^RUN_ID=' "$ENV" | cut -d= -f2)
  [[ "$RUN_ID" =~ ^[0-9]+$ ]] && ok "run-env-has-runid" || bad "run-env-has-runid" "no RUN_ID"

  # slugs per batch (sorted order: chiller cooling-tower pump | vav)
  local F0="$d/mep/dev/audit/_audit-0.md" F1="$d/mep/dev/audit/_audit-1.md"
  mk_clean() {
    {
      printf 'VALIDATED\tchiller\t%s\n' "$RUN_ID"
      printf 'VALIDATED\tcooling-tower\t%s\n' "$RUN_ID"
      printf 'VALIDATED\tpump\t%s\n' "$RUN_ID"
      printf 'CORRECTION\tchiller\t"44 F" -> "42 F" per [ashrae]\n'
      printf 'SOFTSPOT\tpump\tPumps rarely exceed 80%% efficiency.\tno scoped source\n'
    } > "$F0"
    printf 'VALIDATED\tvav\t%s\n' "$RUN_ID" > "$F1"
  }
  mk_clean
  if bash "$0" gate mep >/dev/null 2>&1; then ok "gate-clean-passes"; else bad "gate-clean-passes" "clean gate failed"; fi

  # (a) drop the vav receipt row → present-but-incomplete: gate-batch passes (file
  #     present, has a VALIDATED row for... nothing now), check-coverage FAILS naming vav.
  local out rc
  mk_clean; : > "$F1"   # F1 must stay non-empty + have a VALIDATED row or gate-batch trips first;
  printf 'VALIDATED\tnot-vav\t%s\n' "$RUN_ID" > "$F1"   # a receipt for an UNKNOWN slug: vav omitted + not-vav unknown
  out=$(bash "$0" gate mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qw 'vav' <<<"$out"; then
    ok "gate-fails-naming-dropped-receipt"
  else
    bad "gate-fails-naming-dropped-receipt" "expected nonzero + 'vav', rc=$rc out=$out"
  fi

  # (a2) a receipt carrying a STALE/absent RUN_ID in col 3 → gate FAILS naming the
  #      slug, even though the file is fresh and coverage-complete.
  mk_clean
  printf 'VALIDATED\tvav\t999\n' > "$F1"   # wrong RUN_ID (999 != this run's)
  out=$(bash "$0" gate mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -qw 'vav' <<<"$out" && grep -q 'RUN_ID' <<<"$out"; then
    ok "gate-fails-on-stale-runid"
  else
    bad "gate-fails-on-stale-runid" "expected nonzero + 'vav' + RUN_ID, rc=$rc out=$out"
  fi

  # (b) whole batch file deleted → gate-batch trips first, failing by path.
  mk_clean; rm -f "$F1"
  out=$(bash "$0" gate mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -q '_audit-1.md' <<<"$out"; then
    ok "gate-fails-on-deleted-file"
  else
    bad "gate-fails-on-deleted-file" "expected nonzero + path, rc=$rc out=$out"
  fi

  # finish must FAIL on a dispatched batch file that vanished (the silent-shrink
  # the old glob+`cat 2>/dev/null` bug allowed), not quietly emit a short report.
  mk_clean; rm -f "$F1"
  out=$(bash "$0" finish mep 2>&1) && rc=0 || rc=$?
  if [[ "$rc" -ne 0 ]] && grep -q '_audit-1.md' <<<"$out"; then
    ok "finish-fails-on-missing-batch"
  else
    bad "finish-fails-on-missing-batch" "expected nonzero + path, rc=$rc out=$out"
  fi

  # finish: report + soft-spots with correct counts (1 correction, 1 soft spot).
  mk_clean
  out=$(bash "$0" finish mep 2>&1) || bad "finish-runs" "finish exited nonzero"
  local REPORT="$d/mep/dev/audit/report.md" SS="$d/mep/dev/audit/soft-spots.tsv"
  if grep -q 'articles=4 corrections=1 softspots=1' <<<"$out" \
     && [[ -f "$REPORT" && -f "$SS" ]] \
     && grep -q $'^pump\tPumps rarely exceed' "$SS"; then
    ok "finish-writes-report-and-softspots"
  else
    bad "finish-writes-report-and-softspots" "out=$out ss=$(cat "$SS" 2>/dev/null)"
  fi
  # finish cleaned up the transient run-state.
  [[ ! -f "$DISP" && ! -f "$ENV" ]] && ok "finish-cleans-run-state" || bad "finish-cleans-run-state" "run-state survived"

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
  *) echo "usage: audit.sh {prep|gate|finish} <stack>  |  audit.sh --self-check" >&2; exit 1 ;;
esac
