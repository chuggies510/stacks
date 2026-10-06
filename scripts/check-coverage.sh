#!/usr/bin/env bash
set -euo pipefail

# Reconcile a dispatch manifest against per-item receipts, PER BATCH. Proves every
# dispatched work item produced exactly one receipt in its own batch's file: fails
# by NAME on omissions (dispatched, no receipt), duplicates (a receipt twice), and
# unknowns (a receipt for something never dispatched to that batch). Substrate-
# agnostic: it reads files on disk and knows nothing about Agent-vs-Workflow fan-out.
#
# Usage:
#   bash check-coverage.sh [--verdict TAG] <dispatch.tsv> <tag>=<file>...
#   bash check-coverage.sh --self-check
#
# Each <tag>=<file> pair is checked against only the manifest rows whose col-1
# batch_tag == tag, against only the receipts in THAT file. So a cross-batch
# misattribution (agent A emits an id dispatched to B while B omits it) surfaces as
# a batch-B omission AND a batch-A unknown; a union over all files would pass it
# (#92). Offenders are named batch/id. Manifest-wide defects (malformed row,
# double-dispatch), missing files, and receipt-dups are global.
#
# Arguments:
#   --verdict TAG    Count a receipt row only when its col-1 verdict equals TAG.
#                    For a findings file that MIXES a per-item receipt row with
#                    per-item detail rows sharing the id column — audit's
#                    _audit-<tag>.md carries VALIDATED (receipt) plus CORRECTION
#                    rows (detail), all keyed on slug in col 2, so without the
#                    filter a corrected article's slug double-counts as a receipt.
#                    Omit (enrich) when every tab row is already a receipt.
#   <dispatch.tsv>   The dispatch manifest (see below).
#   <tag>=<file>...  One pair per batch_tag in the manifest. A file that does NOT
#                    exist is a FATAL coverage failure (named on stderr): an agent
#                    that wrote no file failed. A manifest tag with no pair is
#                    fatal too, else that batch would be silently skipped.
#
# Exit codes:
#   0   Dispatched id set == emitted id set exactly, per batch. Prints a PASS line.
#   1   Any omission, duplicate, unknown, missing output file, unpaired batch tag,
#       double-dispatched id, or malformed manifest row; each category's offenders
#       are named on stderr. Also usage errors.
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
# Receipt rows (what agents emit into their output files) carry the item_id in
# column 2, one row per ASSIGNED id including explicit no-op verdicts (NOSOURCE, a
# clean VALIDATED). A receipt line is any line with at least 2 tab-separated
# columns and a non-empty col 2; prose / markdown / blank lines (no tabs) are
# ignored, so receipts can share a file with report text.
# ---------------------------------------------------------------------------

usage() {
  echo "usage: check-coverage.sh [--verdict TAG] <dispatch.tsv> <tag>=<file>..." >&2
  echo "       check-coverage.sh --self-check" >&2
  exit 1
}

reconcile() {
  [[ $# -ge 3 && -n "$2" ]] || usage
  local verdict=$1 dispatch=$2; shift 2   # remaining args are <tag>=<file> pairs
  [[ -f "$dispatch" ]] || {
    echo "check-coverage.sh: dispatch manifest not found: $dispatch" >&2; exit 1; }

  local tmp; tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  # Manifest-wide defects fail by name instead of passing silently: a non-blank row
  # with an empty col-2 id (malformed), and the same id in two rows (double-dispatch,
  # where a single receipt would look complete).
  awk -F'\t' '!/^[[:space:]]*$/ && $2=="" {print NR}' "$dispatch" > "$tmp/malformed"
  awk -F'\t' '$2!="" {print $2}' "$dispatch" > "$tmp/dispatched_all"
  sort "$tmp/dispatched_all" | uniq -d > "$tmp/dispatch_dups"

  : > "$tmp/emitted_all"   # every receipt id (dups preserved) for global dup check
  : > "$tmp/missing"
  : > "$tmp/omissions"     # "tag<TAB>id": expected for this batch, absent from its file
  : > "$tmp/unknowns"      # "tag<TAB>id": in this file, not expected for this batch
  : > "$tmp/pair_tags"     # tags actually supplied as <tag>=<file> pairs

  local pair tag file
  for pair in "$@"; do
    tag=${pair%%=*}
    file=${pair#*=}
    echo "$tag" >> "$tmp/pair_tags"
    # A MISSING output path is fatal (an agent that wrote no file is a coverage
    # failure by definition), not merely "its ids omit".
    if [[ ! -e "$file" ]]; then
      echo "$file" >> "$tmp/missing"
      continue
    fi
    # Expected ids for THIS batch: manifest col-2 where col-1 == tag.
    awk -F'\t' -v t="$tag" '$1==t && $2!="" {print $2}' "$dispatch" | sort -u > "$tmp/exp"
    # Emitted ids in THIS file only. With --verdict, a receipt line must ALSO lead
    # with that verdict in col 1, so detail rows reusing the id column don't count.
    awk -F'\t' -v v="$verdict" \
      'NF>=2 && $2!="" && (v=="" || $1==v) {print $2}' "$file" > "$tmp/emit_raw"
    cat "$tmp/emit_raw" >> "$tmp/emitted_all"
    sort -u "$tmp/emit_raw" > "$tmp/emit_u"
    comm -23 "$tmp/exp" "$tmp/emit_u" | awk -v t="$tag" '{print t"\t"$0}' >> "$tmp/omissions"
    comm -13 "$tmp/exp" "$tmp/emit_u" | awk -v t="$tag" '{print t"\t"$0}' >> "$tmp/unknowns"
  done

  # Every batch_tag in the manifest MUST have a supplied <tag>=<file> pair, else that
  # batch is silently skipped while its ids still count as dispatched.
  awk -F'\t' '$2!="" {print $1}' "$dispatch" | sort -u > "$tmp/manifest_tags"
  sort -u "$tmp/pair_tags" > "$tmp/pair_tags_u"
  comm -23 "$tmp/manifest_tags" "$tmp/pair_tags_u" > "$tmp/unpaired_tags"

  sort "$tmp/emitted_all" | uniq -d > "$tmp/dups"

  local rc=0
  if [[ -s "$tmp/unpaired_tags" ]]; then
    rc=1
    printf 'COVERAGE_FAILURE: %d manifest batch tag(s) with no receipt-file pair: %s\n' \
      "$(wc -l < "$tmp/unpaired_tags" | tr -d ' ')" "$(paste -sd' ' "$tmp/unpaired_tags")" >&2
  fi
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
    printf 'COVERAGE_FAILURE: %d omitted (dispatched to a batch, no receipt in its file) [batch/id]: %s\n' \
      "$(wc -l < "$tmp/omissions" | tr -d ' ')" \
      "$(awk -F'\t' '{print $1"/"$2}' "$tmp/omissions" | paste -sd' ' -)" >&2
  fi
  if [[ -s "$tmp/dups" ]]; then
    rc=1
    printf 'COVERAGE_FAILURE: %d duplicated (receipt seen >1x): %s\n' \
      "$(wc -l < "$tmp/dups" | tr -d ' ')" "$(paste -sd' ' "$tmp/dups")" >&2
  fi
  if [[ -s "$tmp/unknowns" ]]; then
    rc=1
    printf 'COVERAGE_FAILURE: %d unknown (receipt not dispatched to that batch) [batch/id]: %s\n' \
      "$(wc -l < "$tmp/unknowns" | tr -d ' ')" \
      "$(awk -F'\t' '{print $1"/"$2}' "$tmp/unknowns" | paste -sd' ' -)" >&2
  fi

  if [[ $rc -eq 0 ]]; then
    echo "COVERAGE_OK: $(sort -u "$tmp/dispatched_all" | wc -l | tr -d ' ') items dispatched across ${#} batch(es), each receipted in its own batch file"
  fi
  return $rc
}

# Inline red-when-broken self-check: fabricate a manifest + receipt files, assert
# a FAIL carrying the exact anchor phrase naming the offender on each defect and a
# PASS on the clean set. No framework. Run: bash check-coverage.sh --self-check
self_check() {
  local d; d=$(mktemp -d)
  trap 'rm -rf "$d"' RETURN
  local pass=0 fail=0

  # Manifest: two batches, ids a b c (batchA) / d e (batchB).
  printf 'batchA\ta\nbatchA\tb\nbatchA\tc\nbatchB\td\nbatchB\te\n' > "$d/dispatch.tsv"
  local AB=("batchA=$d/outA.txt" "batchB=$d/outB.txt")

  # A clean receipt set: batchA emits a b c, batchB emits d e (verdict<TAB>id).
  mk_clean() {
    printf 'VALIDATED\ta\tRUN1\nVALIDATED\tb\tRUN1\nVALIDATED\tc\tRUN1\n' > "$d/outA.txt"
    printf 'VALIDATED\td\tRUN1\nNOSOURCE\te\tRUN1\n' > "$d/outB.txt"
  }

  # assert: run the script, check its exit code and that its output carries the
  # exact phrase `want` (fixed string; "" for none). A phrase, not a bare id: a
  # one-letter id would match any prose, and the phrase pins the failure CATEGORY.
  check() {
    local name=$1 want_rc=$2 want=$3; shift 3
    local out rc
    out=$( bash "$0" "$@" 2>&1 ) && rc=0 || rc=$?
    if [[ "$rc" -ne "$want_rc" ]]; then
      echo "SELF-CHECK FAIL [$name]: expected exit $want_rc, got $rc" >&2
      echo "$out" | sed 's/^/    /' >&2
      fail=$((fail+1)); return
    fi
    if [[ -n "$want" ]] && ! grep -qF -- "$want" <<<"$out"; then
      echo "SELF-CHECK FAIL [$name]: output did not contain '$want'" >&2
      echo "$out" | sed 's/^/    /' >&2
      fail=$((fail+1)); return
    fi
    echo "SELF-CHECK PASS [$name]: exit $rc$([[ -n "$want" ]] && echo ", found '$want'")"
    [[ -n "$out" ]] && echo "$out" | sed 's/^/    /'
    pass=$((pass+1))
  }

  local OMIT='no receipt in its file) [batch/id]: ' UNK='not dispatched to that batch) [batch/id]: '

  # (0) clean set → PASS (exit 0)
  mk_clean
  check "clean-set" 0 "COVERAGE_OK: 5 items dispatched across 2 batch(es)" "$d/dispatch.tsv" "${AB[@]}"

  # (a) one dropped id: batchA omits 'b'
  mk_clean
  printf 'VALIDATED\ta\tRUN1\nVALIDATED\tc\tRUN1\n' > "$d/outA.txt"
  check "dropped-id (b omitted)" 1 "${OMIT}batchA/b" "$d/dispatch.tsv" "${AB[@]}"

  # (b) one duplicated id: batchB emits 'd' twice
  mk_clean
  printf 'VALIDATED\td\tRUN1\nNOSOURCE\te\tRUN1\nVALIDATED\td\tRUN1\n' > "$d/outB.txt"
  check "duplicated-id (d twice)" 1 "(receipt seen >1x): d" "$d/dispatch.tsv" "${AB[@]}"

  # (c) one unknown id: batchB emits 'z' never dispatched
  mk_clean
  printf 'VALIDATED\td\tRUN1\nNOSOURCE\te\tRUN1\nVALIDATED\tz\tRUN1\n' > "$d/outB.txt"
  check "unknown-id (z)" 1 "${UNK}batchB/z" "$d/dispatch.tsv" "${AB[@]}"

  # (d) one deleted output file: outB.txt gone → named as missing
  mk_clean
  rm -f "$d/outB.txt"
  check "deleted-file (outB missing)" 1 "output file(s) missing: $d/outB.txt" "$d/dispatch.tsv" "${AB[@]}"

  # (e) missing file whose ids ARE covered by another batch's file → MUST still fail
  #     naming the file (a union once let the other file mask the miss).
  printf 'V\ta\tR\nV\tb\tR\nV\tc\tR\nV\td\tR\nV\te\tR\n' > "$d/outA.txt"
  rm -f "$d/outB.txt"
  check "missing-file-covered-elsewhere" 1 "output file(s) missing: $d/outB.txt" "$d/dispatch.tsv" "${AB[@]}"

  # (f) double-dispatch: 'a' in two manifest rows → fail naming 'a' (a lone receipt
  #     used to look complete). batchB's file carries no 'a', so the dispatch-dup
  #     message is the one that fires, not a receipt dup.
  printf 'batchA\ta\nbatchB\ta\nbatchA\tc\n' > "$d/dispatch_dup.tsv"
  printf 'V\ta\tR\nV\tc\tR\n' > "$d/outA.txt"
  printf 'V\tq\tR\n' > "$d/outB.txt"
  check "double-dispatch (a twice)" 1 "id(s) dispatched more than once: a" "$d/dispatch_dup.tsv" "${AB[@]}"

  # (g) malformed manifest row: non-blank row with empty col-2 id → fail, naming line 2
  #     (extra metadata cols are allowed, an empty id is not).
  printf 'batchA\ta\nbatchA\t\nbatchA\tc\n' > "$d/dispatch_bad.tsv"
  printf 'V\ta\tR\nV\tc\tR\n' > "$d/outA.txt"
  check "malformed-manifest (empty id)" 1 "empty item_id at line(s): 2" "$d/dispatch_bad.tsv" "batchA=$d/outA.txt"

  # (h) metadata columns allowed: a 5-col manifest (enrich's shape) passes when the
  #     col-2 receipts are complete.
  printf 'batchA\ta\tslug-a\tclaim\treason\nbatchA\tb\tslug-b\tclaim\treason\n' > "$d/dispatch_meta.tsv"
  printf 'CANDIDATE\ta\tR\nNOSOURCE\tb\tR\n' > "$d/outA.txt"
  check "metadata-cols-ok (5-col manifest)" 0 "COVERAGE_OK: 2 items" "$d/dispatch_meta.tsv" "batchA=$d/outA.txt"

  # --verdict filter: a findings file that mixes a per-item receipt row (VALIDATED)
  # with per-item DETAIL rows sharing col 2 (audit's CORRECTION keyed on
  # slug). Without --verdict, the detail row's slug double-counts as a receipt.
  printf 'batchA\ta\nbatchA\tb\nbatchA\tc\n' > "$d/dispatch_mix.tsv"
  printf 'VALIDATED\ta\tRUN1\nCORRECTION\ta\t"x"->"y"\nVALIDATED\tb\tRUN1\nCORRECTION\tb\tremoved a claim\nVALIDATED\tc\tRUN1\n' > "$d/outMix.txt"
  # (i) --verdict VALIDATED → clean PASS
  check "verdict-filter clean (mixed rows)" 0 "COVERAGE_OK: 3 items" --verdict VALIDATED "$d/dispatch_mix.tsv" "batchA=$d/outMix.txt"
  # (j) same file WITHOUT --verdict → 'a' and 'b' double-count as duplicates.
  check "verdict-off double-counts detail (a b dup)" 1 "(receipt seen >1x): a b" "$d/dispatch_mix.tsv" "batchA=$d/outMix.txt"
  # (k) --verdict still catches a genuinely dropped receipt: no VALIDATED for c.
  printf 'VALIDATED\ta\tRUN1\nCORRECTION\tc\t"x"->"y"\nVALIDATED\tb\tRUN1\n' > "$d/outMix.txt"
  check "verdict-filter drops non-receipt (c omitted)" 1 "${OMIT}batchA/c" --verdict VALIDATED "$d/dispatch_mix.tsv" "batchA=$d/outMix.txt"

  # (l) CROSS-BATCH MISATTRIBUTION (#92): 'd' is dispatched to batchB, but batchA's
  #     file emits it and batchB's file omits it. A union over both files sees d with
  #     dispatched==emitted and would pass. Per batch: batchB/d omitted AND batchA/d unknown.
  printf 'VALIDATED\ta\tRUN1\nVALIDATED\tb\tRUN1\nVALIDATED\tc\tRUN1\nVALIDATED\td\tRUN1\n' > "$d/outA.txt"
  printf 'NOSOURCE\te\tRUN1\n' > "$d/outB.txt"
  check "cross-batch omission (d dropped by B)" 1 "${OMIT}batchB/d" "$d/dispatch.tsv" "${AB[@]}"
  check "cross-batch unknown (d stray in A)" 1 "${UNK}batchA/d" "$d/dispatch.tsv" "${AB[@]}"

  # (m) unpaired batch tag: manifest has batchA + batchB but only batchA gets a pair.
  #     batchB is silently skipped without this guard → must FAIL naming batchB.
  mk_clean
  check "unpaired-tag (batchB no pair)" 1 "no receipt-file pair: batchB" "$d/dispatch.tsv" "batchA=$d/outA.txt"

  echo "---"
  echo "self-check: $pass passed, $fail failed"
  [[ "$fail" -eq 0 ]]
}

# Arg parsing runs after the function defs so --self-check can call self_check
# (bash defines functions top-to-bottom as it executes).
VERDICT=""   # empty = every tab row is a receipt (enrich); set = only col-1==VERDICT rows count (audit)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-check) self_check; exit $? ;;
    --verdict) VERDICT=${2:-}; shift 2 || usage ;;
    --) shift; break ;;
    -*) echo "check-coverage.sh: unknown option '$1'" >&2; usage ;;
    *) break ;;
  esac
done

# Anything reaching here is a real reconciliation run.
reconcile "$VERDICT" "$@"
