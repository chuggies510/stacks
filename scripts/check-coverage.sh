#!/usr/bin/env bash
set -euo pipefail

# Reconcile a dispatch manifest against per-item receipts. Proves every
# dispatched work item produced exactly one receipt: fails by NAME on omissions
# (dispatched, no receipt), duplicates (a receipt twice), and unknowns (a
# receipt for something never dispatched). Substrate-agnostic — it reads files
# on disk and knows nothing about Agent-vs-Workflow fan-out.
#
# Usage:
#   bash check-coverage.sh [--field N] [--verdict TAG] <dispatch.tsv> <output-file>...
#   bash check-coverage.sh --self-check
#
# Arguments:
#   --field N        1-based column holding the item_id in a RECEIPT row
#                    (default 2). The dispatch manifest's item_id is always
#                    column 2 (see manifest shape below); --field configures
#                    only the output/receipt column, which varies per pipeline
#                    (validator: VALIDATED<TAB>{slug}<TAB>{RUN_ID} → col 2;
#                    enrichment: verdict<TAB>gap_id<TAB>... → col 2).
#   --verdict TAG    Count a receipt row only when its col-1 verdict equals TAG.
#                    For a findings file that MIXES a per-item receipt row with
#                    per-item detail rows sharing the id column — audit's
#                    _audit-<tag>.md carries VALIDATED (receipt) plus CORRECTION/
#                    SOFTSPOT (detail), all keyed on slug in col 2, so without the
#                    filter a corrected article's slug double-counts as a receipt.
#                    Omit (enrich) when every tab row is already a receipt.
#   <dispatch.tsv>   The dispatch manifest (see below).
#   <output-file>... One or more receipt-bearing output files. A path that does
#                    NOT exist is a FATAL coverage failure (named on stderr): an
#                    agent that wrote no file failed, regardless of whether some
#                    other file happens to cover its ids. This kills the old
#                    `cat _audit-*.md 2>/dev/null || true` silent-shrink.
#
# Exit codes:
#   0   Dispatched id set == emitted id set exactly. Prints a PASS line.
#   1   Any omission, duplicate, unknown, missing output file, double-dispatched
#       id, or malformed manifest row; each category's offenders are named on
#       stderr. Also usage errors.
#
# ---------------------------------------------------------------------------
# Run-state convention (this header is the convention's home — no separate doc)
#
# Pipeline state crosses phases through checked-in files under dev/<phase>/,
# NEVER shell env (a var set in one SKILL.md Bash block is empty in the next —
# the harness re-inits the shell each call; this is the #72 root-cause fix).
#
#   dev/<phase>/run.env       KEY=VAL lines (the proven _dedup-meta.txt pattern)
#                             carrying RUN_ID (the dispatch epoch/nonce), item
#                             counts, and paths. Later phases source/grep it.
#
#   dev/<phase>/dispatch.tsv  The dispatch manifest, one row per dispatched work
#                             item:  batch_tag<TAB>item_id[<TAB>metadata...]
#                             batch_tag groups items into one agent's assignment;
#                             item_id (col 2) is the natural per-pipeline key
#                             (source path, concept slug, article slug, gap_id).
#                             Cols 3+ are OPTIONAL per-pipeline metadata (e.g.
#                             enrich carries slug/claim/reason so the manifest is
#                             also the gap file) and are ignored for reconciliation.
#                             A non-blank row with an empty col-2 id is malformed
#                             and fails; the same id in two rows is a double-
#                             dispatch and fails (a lone receipt would mask it).
#
# Receipt rows (what agents emit into their output files) carry the item_id in a
# fixed column (--field, default 2), one row per ASSIGNED id including explicit
# no-op verdicts (NOSOURCE, a clean VALIDATED). A receipt line is any line with
# at least --field tab-separated columns and a non-empty id column; prose /
# markdown / blank lines (no tabs) are ignored, so receipts can share a file
# with report text.
# ---------------------------------------------------------------------------

usage() {
  echo "usage: check-coverage.sh [--field N] [--verdict TAG] <dispatch.tsv> <output-file>..." >&2
  echo "       check-coverage.sh --self-check" >&2
  exit 1
}

run_reconcile() {
  local field=$1; shift
  local verdict=$1; shift
  local dispatch=$1; shift

  [[ -n "$dispatch" && $# -ge 1 ]] || usage
  [[ "$field" =~ ^[0-9]+$ && "$field" -ge 1 ]] || {
    echo "check-coverage.sh: --field must be a positive integer, got '$field'" >&2; exit 1; }
  [[ -f "$dispatch" ]] || {
    echo "check-coverage.sh: dispatch manifest not found: $dispatch" >&2; exit 1; }

  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  # Dispatched ids from manifest col 2 (col 1 is batch_tag; cols 3+ are optional
  # per-pipeline metadata, ignored). Two manifest defects fail by name instead of
  # passing silently: a non-blank row with an empty col-2 id (malformed), and the
  # same id in two rows (double-dispatch — a single receipt would look complete).
  awk -F'\t' '!/^[[:space:]]*$/ && $2=="" {print NR}' "$dispatch" > "$tmp/malformed"
  awk -F'\t' '$2!="" {print $2}' "$dispatch" > "$tmp/dispatched_all"
  sort "$tmp/dispatched_all" | uniq -d > "$tmp/dispatch_dups"
  sort -u "$tmp/dispatched_all" > "$tmp/dispatched"

  # Emitted ids across ALL output files, dups preserved for receipt-dup detection.
  # A MISSING output path is fatal (an agent that wrote no file is a coverage
  # failure by definition), NOT merely "its ids omit" — else another batch's file
  # covering those ids would mask the miss.
  : > "$tmp/emitted_all"
  : > "$tmp/missing"
  local f
  for f in "$@"; do
    if [[ ! -e "$f" ]]; then
      echo "$f" >> "$tmp/missing"
      continue
    fi
    # When --verdict is set, a receipt line must ALSO lead with that verdict in
    # col 1 — so a findings file mixing a per-item receipt row (VALIDATED) with
    # per-item detail rows that reuse the id column (audit's CORRECTION/SOFTSPOT
    # keyed on slug) counts only the receipts, not the detail.
    awk -F'\t' -v c="$field" -v v="$verdict" \
      'NF>=c && $c!="" && (v=="" || $1==v) {print $c}' "$f" >> "$tmp/emitted_all"
  done

  sort -u "$tmp/emitted_all" > "$tmp/emitted_u"
  sort "$tmp/emitted_all" | uniq -d > "$tmp/dups"

  comm -23 "$tmp/dispatched" "$tmp/emitted_u" > "$tmp/omissions"
  comm -13 "$tmp/dispatched" "$tmp/emitted_u" > "$tmp/unknowns"

  local rc=0
  if [[ -s "$tmp/malformed" ]]; then
    rc=1
    printf 'COVERAGE_FAILURE: %d malformed manifest row(s), empty item_id at line(s): %s\n' \
      "$(wc -l < "$tmp/malformed" | tr -d ' ')" "$(paste -sd' ' "$tmp/malformed")" >&2
  fi
  if [[ -s "$tmp/dispatch_dups" ]]; then
    rc=1
    printf 'COVERAGE_FAILURE: %d id(s) dispatched more than once: %s\n' \
      "$(wc -l < "$tmp/dispatch_dups" | tr -d ' ')" "$(paste -sd' ' "$tmp/dispatch_dups")" >&2
  fi
  if [[ -s "$tmp/missing" ]]; then
    rc=1
    printf 'COVERAGE_FAILURE: %d output file(s) missing: %s\n' \
      "$(wc -l < "$tmp/missing" | tr -d ' ')" "$(paste -sd' ' "$tmp/missing")" >&2
  fi
  if [[ -s "$tmp/omissions" ]]; then
    rc=1
    printf 'COVERAGE_FAILURE: %d omitted (dispatched, no receipt): %s\n' \
      "$(wc -l < "$tmp/omissions" | tr -d ' ')" "$(paste -sd' ' "$tmp/omissions")" >&2
  fi
  if [[ -s "$tmp/dups" ]]; then
    rc=1
    printf 'COVERAGE_FAILURE: %d duplicated (receipt seen >1x): %s\n' \
      "$(wc -l < "$tmp/dups" | tr -d ' ')" "$(paste -sd' ' "$tmp/dups")" >&2
  fi
  if [[ -s "$tmp/unknowns" ]]; then
    rc=1
    printf 'COVERAGE_FAILURE: %d unknown (receipt, never dispatched): %s\n' \
      "$(wc -l < "$tmp/unknowns" | tr -d ' ')" "$(paste -sd' ' "$tmp/unknowns")" >&2
  fi

  if [[ $rc -eq 0 ]]; then
    echo "COVERAGE_OK: $(wc -l < "$tmp/dispatched" | tr -d ' ') items dispatched, all receipted exactly once"
  fi
  return $rc
}

# Inline red-when-broken self-check: fabricate a manifest + receipt files, assert
# a FAIL naming the offending id on each defect and a PASS on the clean set. No
# framework. Run: bash check-coverage.sh --self-check
self_check() {
  local d; d=$(mktemp -d)
  trap 'rm -rf "$d"' RETURN
  local pass=0 fail=0

  # Manifest: two batches, ids a b c (batchA) / d e (batchB).
  printf 'batchA\ta\nbatchA\tb\nbatchA\tc\nbatchB\td\nbatchB\te\n' > "$d/dispatch.tsv"

  # A clean receipt set: batchA emits a b c, batchB emits d e (verdict<TAB>id).
  mk_clean() {
    printf 'VALIDATED\ta\tRUN1\nVALIDATED\tb\tRUN1\nVALIDATED\tc\tRUN1\n' > "$d/outA.txt"
    printf 'VALIDATED\td\tRUN1\nNOSOURCE\te\tRUN1\n' > "$d/outB.txt"
  }

  # assert: run reconcile in a subshell, capture rc + stderr, check expectation.
  # want_rc: expected exit code. want_id: id that MUST appear in output (or "").
  check() {
    local name=$1 want_rc=$2 want_id=$3; shift 3
    local out rc
    out=$( bash "$0" --field 2 "$@" 2>&1 ) && rc=0 || rc=$?
    if [[ "$rc" -ne "$want_rc" ]]; then
      echo "SELF-CHECK FAIL [$name]: expected exit $want_rc, got $rc" >&2
      echo "$out" | sed 's/^/    /' >&2
      fail=$((fail+1)); return
    fi
    if [[ -n "$want_id" ]] && ! grep -qw "$want_id" <<<"$out"; then
      echo "SELF-CHECK FAIL [$name]: output did not name id '$want_id'" >&2
      echo "$out" | sed 's/^/    /' >&2
      fail=$((fail+1)); return
    fi
    echo "SELF-CHECK PASS [$name]: exit $rc$([[ -n "$want_id" ]] && echo ", named '$want_id'")"
    [[ -n "$out" ]] && echo "$out" | sed 's/^/    /'
    pass=$((pass+1))
  }

  # (0) clean set → PASS (exit 0)
  mk_clean
  check "clean-set" 0 "" "$d/dispatch.tsv" "$d/outA.txt" "$d/outB.txt"

  # (a) one dropped id: batchA omits 'b'
  mk_clean
  printf 'VALIDATED\ta\tRUN1\nVALIDATED\tc\tRUN1\n' > "$d/outA.txt"
  check "dropped-id (b omitted)" 1 "b" "$d/dispatch.tsv" "$d/outA.txt" "$d/outB.txt"

  # (b) one duplicated id: batchB emits 'd' twice
  mk_clean
  printf 'VALIDATED\td\tRUN1\nNOSOURCE\te\tRUN1\nVALIDATED\td\tRUN1\n' > "$d/outB.txt"
  check "duplicated-id (d twice)" 1 "d" "$d/dispatch.tsv" "$d/outA.txt" "$d/outB.txt"

  # (c) one unknown id: batchB emits 'z' never dispatched
  mk_clean
  printf 'VALIDATED\td\tRUN1\nNOSOURCE\te\tRUN1\nVALIDATED\tz\tRUN1\n' > "$d/outB.txt"
  check "unknown-id (z)" 1 "z" "$d/dispatch.tsv" "$d/outA.txt" "$d/outB.txt"

  # (d) one deleted output file: outB.txt gone → its ids d, e omitted
  mk_clean
  rm -f "$d/outB.txt"
  check "deleted-file (d,e omitted)" 1 "d" "$d/dispatch.tsv" "$d/outA.txt" "$d/outB.txt"
  # and the file's other id is named too
  mk_clean; rm -f "$d/outB.txt"
  check "deleted-file names e too" 1 "e" "$d/dispatch.tsv" "$d/outA.txt" "$d/outB.txt"

  # (f) missing file whose ids ARE covered elsewhere → MUST still fail (codex #2
  #     regression: previously passed because receipts union globally).
  printf 'V\ta\tR\nV\tb\tR\nV\tc\tR\nV\td\tR\nV\te\tR\n' > "$d/outA.txt"
  rm -f "$d/outB.txt"
  check "missing-file-covered (still fails)" 1 "" "$d/dispatch.tsv" "$d/outA.txt" "$d/outB.txt"

  # (g) double-dispatch: 'a' in two manifest rows → fail naming 'a' (codex #1;
  #     previously deduped and passed with a single receipt).
  printf 'batchA\ta\nbatchB\ta\nbatchA\tc\n' > "$d/dispatch_dup.tsv"
  printf 'V\ta\tR\nV\tc\tR\n' > "$d/outA.txt"
  check "double-dispatch (a twice)" 1 "a" "$d/dispatch_dup.tsv" "$d/outA.txt"

  # (h) malformed manifest row: non-blank row with empty col-2 id → fail (codex #3,
  #     adapted — extra metadata cols are allowed, an empty id is not).
  printf 'batchA\ta\nbatchA\t\nbatchA\tc\n' > "$d/dispatch_bad.tsv"
  printf 'V\ta\tR\nV\tc\tR\n' > "$d/outA.txt"
  check "malformed-manifest (empty id)" 1 "" "$d/dispatch_bad.tsv" "$d/outA.txt"

  # (i) metadata columns allowed: a 5-col manifest (enrich's shape) still passes
  #     when receipts on col 2 are complete.
  printf 'batchA\ta\tslug-a\tclaim\treason\nbatchA\tb\tslug-b\tclaim\treason\n' > "$d/dispatch_meta.tsv"
  printf 'CANDIDATE\ta\tR\nNOSOURCE\tb\tR\n' > "$d/outA.txt"
  check "metadata-cols-ok (5-col manifest)" 0 "" "$d/dispatch_meta.tsv" "$d/outA.txt"

  # --verdict filter: a findings file that mixes a per-item receipt row (VALIDATED)
  # with per-item DETAIL rows sharing col-2 (audit's CORRECTION/SOFTSPOT keyed on
  # slug). Without --verdict, the detail row's slug double-counts as a receipt →
  # false duplicate. With --verdict VALIDATED, only receipt rows count.
  check_v() {   # like check() but injects --verdict as the leading arg
    local name=$1 want_rc=$2 want_id=$3 verdict=$4; shift 4
    local out rc
    out=$( bash "$0" --verdict "$verdict" --field 2 "$@" 2>&1 ) && rc=0 || rc=$?
    if [[ "$rc" -ne "$want_rc" ]]; then
      echo "SELF-CHECK FAIL [$name]: expected exit $want_rc, got $rc" >&2
      echo "$out" | sed 's/^/    /' >&2; fail=$((fail+1)); return
    fi
    if [[ -n "$want_id" ]] && ! grep -qw "$want_id" <<<"$out"; then
      echo "SELF-CHECK FAIL [$name]: output did not name id '$want_id'" >&2
      echo "$out" | sed 's/^/    /' >&2; fail=$((fail+1)); return
    fi
    echo "SELF-CHECK PASS [$name]: exit $rc$([[ -n "$want_id" ]] && echo ", named '$want_id'")"
    pass=$((pass+1))
  }
  # (j) mixed receipt+detail file: VALIDATED a,b,c receipts + CORRECTION on a +
  #     SOFTSPOT on b. --verdict VALIDATED → clean PASS.
  printf 'batchA\ta\nbatchA\tb\nbatchA\tc\n' > "$d/dispatch_mix.tsv"
  printf 'VALIDATED\ta\tRUN1\nCORRECTION\ta\t"x"->"y"\nVALIDATED\tb\tRUN1\nSOFTSPOT\tb\tsome claim\tno source\nVALIDATED\tc\tRUN1\n' > "$d/outMix.txt"
  check_v "verdict-filter clean (mixed rows)" 0 "" "VALIDATED" "$d/dispatch_mix.tsv" "$d/outMix.txt"

  # (k) same mixed file WITHOUT --verdict → 'a' and 'b' double-count as duplicates.
  check "verdict-off double-counts detail (a dup)" 1 "a" "$d/dispatch_mix.tsv" "$d/outMix.txt"

  # (l) --verdict still catches a genuinely dropped receipt: no VALIDATED for c.
  printf 'VALIDATED\ta\tRUN1\nCORRECTION\tc\t"x"->"y"\nVALIDATED\tb\tRUN1\n' > "$d/outMix.txt"
  check_v "verdict-filter drops non-receipt (c omitted)" 1 "c" "VALIDATED" "$d/dispatch_mix.tsv" "$d/outMix.txt"

  echo "---"
  echo "self-check: $pass passed, $fail failed"
  [[ "$fail" -eq 0 ]]
}

# Arg parsing runs after the function defs so --self-check can call self_check
# (bash defines functions top-to-bottom as it executes).
FIELD=2
VERDICT=""   # empty = every tab row is a receipt (enrich); set = only col-1==VERDICT rows count (audit)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-check) self_check; exit $? ;;
    --field) FIELD=${2:-}; shift 2 || usage ;;
    --verdict) VERDICT=${2:-}; shift 2 || usage ;;
    --) shift; break ;;
    -*) echo "check-coverage.sh: unknown option '$1'" >&2; usage ;;
    *) break ;;
  esac
done

# Anything reaching here is a real reconciliation run.
run_reconcile "$FIELD" "$VERDICT" "$@"
