#!/usr/bin/env bash
# validation-verify-summary.sh <verify-dir>
#
# Advisory window (#109): aggregate the per-batch grade JSONs the
# validation-verifier agent wrote (one {batch}.json each, each holding an
# `items[]` array) into a single go/no-go read on whether the local
# validator's per-claim verdicts are safe to trust. Reports poison recall
# (of claims that ARE corrections, how many the local model caught) and the
# false-correction rate (of claims that are NOT corrections, how many the
# local model wrongly altered). Reads only; decides nothing — the human
# reads this after a real batch and calls the flip.
#
#   bash validation-verify-summary.sh <verify-dir>
#   bash validation-verify-summary.sh --self-check
set -euo pipefail

self_check() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  # 4 graded batches, derived from gold_verdict/local_verdict: (a) two poison
  # caught + one clean-left-clean; (b) a missed poison (gold CORRECTION, local
  # CLEAN); (c) a false correction (gold CLEAN, local CORRECTION); (d)
  # INCONSISTENT — the per-item is_poison/poison_caught booleans LIE (is_poison:
  # false, poison_caught:true) but gold_verdict is a CORRECTION the local MISSED
  # (local CLEAN). The summary must DERIVE poison/caught from the verdicts and
  # ignore the booleans, else d's real miss is hidden.
  printf '%s\n' '{"batch":"a","items":[{"claim_id":"1","gold_verdict":"CORRECTION/overstatement","local_verdict":"CORRECTION/overstatement","is_poison":true,"poison_caught":true,"is_false_correction":false},{"claim_id":"2","gold_verdict":"CORRECTION/contradiction","local_verdict":"CORRECTION/overstatement","is_poison":true,"poison_caught":true,"is_false_correction":false},{"claim_id":"3","gold_verdict":"CLEAN","local_verdict":"CLEAN","is_poison":false,"poison_caught":false,"is_false_correction":false}]}' > "$d/a.json"
  printf '%s\n' '{"batch":"b","items":[{"claim_id":"5","gold_verdict":"CORRECTION/overstatement","local_verdict":"CLEAN","is_poison":true,"poison_caught":false,"is_false_correction":false}]}' > "$d/b.json"
  printf '%s\n' '{"batch":"c","items":[{"claim_id":"7","gold_verdict":"CLEAN","local_verdict":"CORRECTION/overstatement","is_poison":false,"poison_caught":false,"is_false_correction":true}]}' > "$d/c.json"
  printf '%s\n' '{"batch":"d","items":[{"claim_id":"9","gold_verdict":"CORRECTION/overstatement","local_verdict":"CLEAN","is_poison":false,"poison_caught":true,"is_false_correction":false}]}' > "$d/d.json"
  local out; out=$(VERIFY_DIR="$d" run 2>&1)
  local fail=0
  grep -q 'graded: 4'                      <<<"$out" || { echo "FAIL: graded count"; fail=1; }
  grep -q 'poison recall: 2/4'              <<<"$out" || { echo "FAIL: poison recall (derived from verdicts, not the lying booleans in d)"; fail=1; }
  grep -q 'false-correction rate: 1/2'      <<<"$out" || { echo "FAIL: false-correction rate (non-poison denominator only)"; fail=1; }
  grep -q 'items graded: 6'                <<<"$out" || { echo "FAIL: items graded count"; fail=1; }
  if [[ $fail -eq 0 ]]; then echo "SELF-CHECK PASS"; else echo "SELF-CHECK FAIL"; return 1; fi
}

run() {
  local dir="${VERIFY_DIR:?}"
  shopt -s nullglob
  local files=("$dir"/*.json)
  shopt -u nullglob
  [[ ${#files[@]} -gt 0 ]] || { echo "No grade JSONs in $dir — run a batch with the validation-verifier agent first."; return 1; }

  # Slurp every batch's items[] and DERIVE the aggregates from the AUTHORITATIVE
  # gold_verdict/local_verdict, never from the per-item is_poison/poison_caught/
  # is_false_correction booleans (those are the agent's own read and can be wrong
  # — codex #109) nor a batch's top-level tally. A claim is poison iff its GOLD
  # verdict is a CORRECTION; it is caught iff the LOCAL verdict is also a
  # CORRECTION (sub-type may differ — a flagged correction is still caught). A
  # false correction is the local CORRECTing a claim gold says is NOT a
  # correction (gold CLEAN or SOFTSPOT), so the denominator is the non-poison
  # items only — never letting a poison item into the false-correction rate.
  jq -s '
    def is_poison: (.gold_verdict // "" | startswith("CORRECTION"));
    def local_corrects: (.local_verdict // "" | startswith("CORRECTION"));
    [.[] | .items[]] as $items
    | {
        graded:              length,
        items_graded:        ($items | length),
        poison_total:        ($items | map(select(is_poison)) | length),
        poison_caught:       ($items | map(select(is_poison and local_corrects)) | length),
        false_correction_total: ($items | map(select(is_poison | not)) | length),
        false_correction_count: ($items | map(select((is_poison | not) and local_corrects)) | length)
      }
    | "graded: \(.graded)\n"
    + "items graded: \(.items_graded)\n"
    + "poison recall: \(.poison_caught)/\(.poison_total)\n"
    + "false-correction rate: \(.false_correction_count)/\(.false_correction_total)"
  ' -r "${files[@]}"

  echo "---"
  echo "A poison recall breach (a claim that IS a correction, called CLEAN) is the dangerous class — nothing downstream catches it. False corrections corrupt truthful content just as badly; both must clear before the local tier judges validation unsupervised."
}

case "${1:-}" in
  --self-check) self_check ;;
  "") echo "Usage: validation-verify-summary.sh <verify-dir> | --self-check" >&2; exit 2 ;;
  *) VERIFY_DIR="$1" run ;;
esac
