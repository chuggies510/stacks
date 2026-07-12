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
  # 4 graded batches: (a) clean — poison caught, no false corrections;
  # (b) missed poison; (c) false correction on a non-poison claim;
  # (d) INCONSISTENT — the agent's own top-level poison_recall claims a full
  # catch (1/1) but its own items[] show poison_caught:false for that claim —
  # the summary must DERIVE the miss from items[] and NOT trust the top-level
  # tally (else d would be miscounted as caught).
  printf '%s\n' '{"batch":"a","items":[{"claim_id":"1","is_poison":true,"poison_caught":true,"is_false_correction":false},{"claim_id":"2","is_poison":true,"poison_caught":true,"is_false_correction":false},{"claim_id":"3","is_poison":false,"poison_caught":false,"is_false_correction":false}],"poison_recall":{"caught":2,"total":2},"false_correction":{"count":0,"total":1}}' > "$d/a.json"
  printf '%s\n' '{"batch":"b","items":[{"claim_id":"5","is_poison":true,"poison_caught":false,"is_false_correction":false}],"poison_recall":{"caught":0,"total":1},"false_correction":{"count":0,"total":0}}' > "$d/b.json"
  printf '%s\n' '{"batch":"c","items":[{"claim_id":"7","is_poison":false,"poison_caught":false,"is_false_correction":true}],"poison_recall":{"caught":0,"total":0},"false_correction":{"count":1,"total":1}}' > "$d/c.json"
  printf '%s\n' '{"batch":"d","items":[{"claim_id":"9","is_poison":true,"poison_caught":false,"is_false_correction":false}],"poison_recall":{"caught":1,"total":1},"false_correction":{"count":0,"total":0}}' > "$d/d.json"
  local out; out=$(VERIFY_DIR="$d" run 2>&1)
  local fail=0
  grep -q 'graded: 4'                      <<<"$out" || { echo "FAIL: graded count"; fail=1; }
  grep -q 'poison recall: 2/4'              <<<"$out" || { echo "FAIL: poison recall (derived from items[], not the inconsistent top-level 1/1 in d)"; fail=1; }
  grep -q 'false-correction rate: 1/2'      <<<"$out" || { echo "FAIL: false-correction rate"; fail=1; }
  grep -q 'items graded: 6'                <<<"$out" || { echo "FAIL: items graded count"; fail=1; }
  if [[ $fail -eq 0 ]]; then echo "SELF-CHECK PASS"; else echo "SELF-CHECK FAIL"; return 1; fi
}

run() {
  local dir="${VERIFY_DIR:?}"
  shopt -s nullglob
  local files=("$dir"/*.json)
  shopt -u nullglob
  [[ ${#files[@]} -gt 0 ]] || { echo "No grade JSONs in $dir — run a batch with the validation-verifier agent first."; return 1; }

  # Slurp every batch's items[] and DERIVE the aggregates from per-item
  # is_poison/poison_caught/is_false_correction fields; never trust a batch's
  # own top-level poison_recall/false_correction tally (an agent can report a
  # count inconsistent with the items it just listed).
  jq -s '
    [.[] | .items[]] as $items
    | {
        graded:              length,
        items_graded:        ($items | length),
        poison_total:        ($items | map(select(.is_poison == true)) | length),
        poison_caught:       ($items | map(select(.is_poison == true and .poison_caught == true)) | length),
        false_correction_total: ($items | map(select(.is_poison == false)) | length),
        false_correction_count: ($items | map(select(.is_false_correction == true)) | length)
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
