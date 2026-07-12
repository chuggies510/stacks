#!/usr/bin/env bash
# synth-verify-summary.sh <verify-dir>
#
# Advisory window (#109): aggregate the per-slug grade JSONs the article-verifier
# wrote (one {slug}.json each) into a single go/no-go read on whether flipping to
# verify-and-fix would produce good output. Reports floor-clearance rate, over-claim
# total, citation-fix volume, recall misses, structural fails. Reads only; decides
# nothing — the human reads this after a real batch and calls the flip.
#
#   bash synth-verify-summary.sh <verify-dir>
#   bash synth-verify-summary.sh --self-check
set -euo pipefail

self_check() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  # 4 graded drafts: (a) clean, (b) over-claim breach, (c) recall breach + citation
  # fixes, (d) INCONSISTENT — the agent claims clears_floors:true but its own recall
  # fields show a miss; the summary must DERIVE non-clearance from the components and
  # NOT trust the boolean (else d would be miscounted as clearing).
  printf '%s\n' '{"slug":"a","recall_total":6,"recall_present":6,"over_claims":0,"structural_pass":true,"clears_floors":true,"citation_fixes":0,"would_fix":[]}' > "$d/a.json"
  printf '%s\n' '{"slug":"b","recall_total":7,"recall_present":7,"over_claims":2,"structural_pass":true,"clears_floors":false,"citation_fixes":1,"would_fix":["x","y"]}' > "$d/b.json"
  printf '%s\n' '{"slug":"c","recall_total":5,"recall_present":4,"over_claims":0,"structural_pass":true,"clears_floors":false,"citation_fixes":3,"would_fix":["z"]}' > "$d/c.json"
  printf '%s\n' '{"slug":"d","recall_total":3,"recall_present":2,"over_claims":0,"structural_pass":true,"clears_floors":true,"citation_fixes":0,"would_fix":[]}' > "$d/d.json"
  local out; out=$(VERIFY_DIR="$d" run 2>&1)
  local fail=0
  grep -q 'graded: 4' <<<"$out"            || { echo "FAIL: graded count"; fail=1; }
  grep -q 'clears floors: 1/4' <<<"$out"   || { echo "FAIL: clears rate (derived, not trusting the boolean)"; fail=1; }
  grep -q 'over-claims (total): 2' <<<"$out" || { echo "FAIL: over-claim total"; fail=1; }
  grep -q 'recall misses: 2' <<<"$out"     || { echo "FAIL: recall misses"; fail=1; }
  grep -q 'citation fixes (total): 4' <<<"$out" || { echo "FAIL: citation fixes"; fail=1; }
  if [[ $fail -eq 0 ]]; then echo "SELF-CHECK PASS"; else echo "SELF-CHECK FAIL"; return 1; fi
}

run() {
  local dir="${VERIFY_DIR:?}"
  shopt -s nullglob
  local files=("$dir"/*.json)
  shopt -u nullglob
  [[ ${#files[@]} -gt 0 ]] || { echo "No grade JSONs in $dir — run a batch with the advisory verifier first."; return 1; }

  # Slurp all grade objects; compute the go/no-go aggregates in one jq pass.
  jq -s '
    {
      graded:        length,
      # DERIVE clearance from the component fields; do not trust the agent-reported
      # .clears_floors boolean (a model can report clears_floors:true while the
      # recall/over_claims fields show a breach). The harness owns this computation.
      clears:        (map(select(((.recall_present // 0) == (.recall_total // 0)) and ((.over_claims // 0) == 0) and (.structural_pass == true))) | length),
      over_total:    (map(.over_claims // 0)   | add),
      cite_total:    (map(.citation_fixes // 0) | add),
      recall_miss:   (map(select((.recall_present // 0) < (.recall_total // 0))) | length),
      struct_fail:   (map(select(.structural_pass == false)) | length)
    }
    | "graded: \(.graded)\n"
    + "clears floors: \(.clears)/\(.graded)\n"
    + "over-claims (total): \(.over_total)\n"
    + "recall misses: \(.recall_miss)\n"
    + "structural fails: \(.struct_fail)\n"
    + "citation fixes (total): \(.cite_total)"
  ' -r "${files[@]}"

  echo "---"
  echo "Floor breaches (over-claim / recall / structure) are what block the flip; citation fixes are expected cheap edits the cloud verify owns."
}

case "${1:-}" in
  --self-check) self_check ;;
  "") echo "Usage: synth-verify-summary.sh <verify-dir> | --self-check" >&2; exit 2 ;;
  *) VERIFY_DIR="$1" run ;;
esac
