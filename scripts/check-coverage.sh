#!/usr/bin/env bash
set -euo pipefail

# Reconcile a dispatch manifest against per-item receipts. Proves every
# dispatched work item produced exactly one receipt: fails by NAME on omissions
# (dispatched, no receipt), duplicates (a receipt twice), and unknowns (a
# receipt for something never dispatched). Substrate-agnostic — it reads files
# on disk and knows nothing about Agent-vs-Workflow fan-out.
#
# Usage:
#   bash check-coverage.sh [--field N] <dispatch.tsv> <output-file>...
#   bash check-coverage.sh --self-check
#
# Arguments:
#   --field N        1-based column holding the item_id in a RECEIPT row
#                    (default 2). The dispatch manifest's item_id is always
#                    column 2 (see manifest shape below); --field configures
#                    only the output/receipt column, which varies per pipeline
#                    (validator: VALIDATED<TAB>{slug}<TAB>{RUN_ID} → col 2;
#                    enrichment: verdict<TAB>gap_id<TAB>... → col 2).
#   <dispatch.tsv>   The dispatch manifest (see below).
#   <output-file>... One or more receipt-bearing output files. A path that does
#                    NOT exist contributes zero receipts, so its dispatched ids
#                    surface as omissions — a missing/empty findings file can
#                    never pass silently (this is the fix that kills the old
#                    `cat _audit-*.md 2>/dev/null || true` silent-shrink).
#
# Exit codes:
#   0   Dispatched id set == emitted id set exactly. Prints a PASS line.
#   1   Any omission, duplicate, or unknown; each category's offending ids are
#       named on stderr. Also usage errors.
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
#                             item:  batch_tag<TAB>item_id
#                             batch_tag groups items into one agent's assignment;
#                             item_id is the natural per-pipeline key (source
#                             path, concept slug, article slug, gap_id).
#
# Receipt rows (what agents emit into their output files) carry the item_id in a
# fixed column (--field, default 2), one row per ASSIGNED id including explicit
# no-op verdicts (NOSOURCE, a clean VALIDATED). A receipt line is any line with
# at least --field tab-separated columns and a non-empty id column; prose /
# markdown / blank lines (no tabs) are ignored, so receipts can share a file
# with report text.
# ---------------------------------------------------------------------------

usage() {
  echo "usage: check-coverage.sh [--field N] <dispatch.tsv> <output-file>..." >&2
  echo "       check-coverage.sh --self-check" >&2
  exit 1
}

run_reconcile() {
  local field=$1; shift
  local dispatch=$1; shift

  [[ -n "$dispatch" && $# -ge 1 ]] || usage
  [[ "$field" =~ ^[0-9]+$ && "$field" -ge 1 ]] || {
    echo "check-coverage.sh: --field must be a positive integer, got '$field'" >&2; exit 1; }
  [[ -f "$dispatch" ]] || {
    echo "check-coverage.sh: dispatch manifest not found: $dispatch" >&2; exit 1; }

  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  # Dispatched ids (manifest col 2), unique. A duplicate dispatch row is a
  # manifest bug out of scope here; dedup so it does not masquerade as a receipt
  # duplicate.
  awk -F'\t' 'NF>=2 && $2!="" {print $2}' "$dispatch" | sort -u > "$tmp/dispatched"

  # Emitted ids across ALL output files, WITH duplicates preserved for dup
  # detection. A path that does not exist contributes nothing (→ its ids omit).
  : > "$tmp/emitted_all"
  local f
  for f in "$@"; do
    if [[ ! -e "$f" ]]; then
      echo "check-coverage.sh: output file not found: $f (its receipts count as omissions)" >&2
      continue
    fi
    awk -F'\t' -v c="$field" 'NF>=c && $c!="" {print $c}' "$f" >> "$tmp/emitted_all"
  done

  sort -u "$tmp/emitted_all" > "$tmp/emitted_u"
  sort "$tmp/emitted_all" | uniq -d > "$tmp/dups"

  comm -23 "$tmp/dispatched" "$tmp/emitted_u" > "$tmp/omissions"
  comm -13 "$tmp/dispatched" "$tmp/emitted_u" > "$tmp/unknowns"

  local rc=0
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

  echo "---"
  echo "self-check: $pass passed, $fail failed"
  [[ "$fail" -eq 0 ]]
}

# Arg parsing runs after the function defs so --self-check can call self_check
# (bash defines functions top-to-bottom as it executes).
FIELD=2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-check) self_check; exit $? ;;
    --field) FIELD=${2:-}; shift 2 || usage ;;
    --) shift; break ;;
    -*) echo "check-coverage.sh: unknown option '$1'" >&2; usage ;;
    *) break ;;
  esac
done

# Anything reaching here is a real reconciliation run.
run_reconcile "$FIELD" "$@"
