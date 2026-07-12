#!/usr/bin/env bash
# enrichment-verify-summary.sh <verify-dir>
#
# Advisory window (#109): aggregate the per-candidate grade JSONs the
# enrichment-verifier wrote (one {gap}.json each) into a single go/no-go read
# on whether the local enrichment loop's CANDIDATEs are safe to stage. Reports
# valid-grounding rate, false-candidate count, tier-mismatch count. Reads only;
# decides nothing beyond the floor line — the human reads this after a real
# batch and calls the flip.
#
# Mirrors synth-verify-summary.sh: false_candidate is DERIVED from the
# grounding_valid field, never trusted from the agent's own would_reject
# boolean — a grade can misreport would_reject:false while grounding_valid is
# false (the same "agent-reported boolean lies" case synth-verify-summary
# guards against), and the harness must still count it as a false candidate.
#
#   bash enrichment-verify-summary.sh <verify-dir>
#   bash enrichment-verify-summary.sh --self-check
set -euo pipefail

self_check() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  # 4 graded candidates: (a) clean, (b) false-candidate correctly flagged,
  # (c) tier mismatch only, (d) INCONSISTENT — the agent reports
  # would_reject:false even though grounding_valid is false; the summary must
  # DERIVE false_candidate from grounding_valid and NOT trust would_reject
  # (else d would be miscounted as safe).
  printf '%s\n' '{"gap":"a","candidate_url":"u-a","grounding_valid":true,"tier_ok":true,"would_reject":false,"reason":""}' > "$d/a.json"
  printf '%s\n' '{"gap":"b","candidate_url":"u-b","grounding_valid":false,"tier_ok":true,"would_reject":true,"reason":"topical only"}' > "$d/b.json"
  printf '%s\n' '{"gap":"c","candidate_url":"u-c","grounding_valid":true,"tier_ok":false,"would_reject":true,"reason":"forum stamped tier 2"}' > "$d/c.json"
  printf '%s\n' '{"gap":"d","candidate_url":"u-d","grounding_valid":false,"tier_ok":true,"would_reject":false,"reason":"agent under-reported its own reject"}' > "$d/d.json"
  local out; out=$(VERIFY_DIR="$d" run 2>&1)
  local fail=0
  grep -q 'graded: 4' <<<"$out"                  || { echo "FAIL: graded count"; fail=1; }
  grep -q 'valid grounding: 2/4' <<<"$out"        || { echo "FAIL: valid grounding (derived, not trusting would_reject)"; fail=1; }
  grep -q 'false candidates: 2' <<<"$out"         || { echo "FAIL: false candidate count (must include the inconsistent 'd' case)"; fail=1; }
  grep -q 'tier mismatches: 1' <<<"$out"          || { echo "FAIL: tier mismatch count"; fail=1; }
  grep -q 'go/no-go: NO-GO' <<<"$out"              || { echo "FAIL: go/no-go line"; fail=1; }
  if [[ $fail -eq 0 ]]; then echo "SELF-CHECK PASS"; else echo "SELF-CHECK FAIL"; return 1; fi
}

run() {
  local dir="${VERIFY_DIR:?}"
  shopt -s nullglob
  local files=("$dir"/*.json)
  shopt -u nullglob
  [[ ${#files[@]} -gt 0 ]] || { echo "No grade JSONs in $dir — run a batch with the enrichment-verifier first."; return 1; }

  # Slurp all grade objects; compute the go/no-go aggregates in one jq pass.
  jq -s '
    {
      graded:         length,
      # DERIVE false_candidate from .grounding_valid; do not trust the agent-
      # reported .would_reject boolean (a grade can report would_reject:false
      # while grounding_valid is false). The harness owns this computation.
      valid_grounding: (map(select(.grounding_valid == true))  | length),
      false_candidate: (map(select(.grounding_valid == false)) | length),
      tier_mismatch:   (map(select(.tier_ok == false))         | length)
    }
    | . + { go: (.false_candidate == 0) }
    | "graded: \(.graded)\n"
    + "valid grounding: \(.valid_grounding)/\(.graded)\n"
    + "false candidates: \(.false_candidate)\n"
    + "tier mismatches: \(.tier_mismatch)\n"
    + "go/no-go: \(if .go then "GO" else "NO-GO" end)"
  ' -r "${files[@]}"

  echo "---"
  echo "A false candidate (hallucinated grounding) blocks the flip — floor 0, same axis the enrichment benchmark gates on. A tier mismatch is a cheap correction the operator can fix on staging, not a blocker."
}

case "${1:-}" in
  --self-check) self_check ;;
  "") echo "Usage: enrichment-verify-summary.sh <verify-dir> | --self-check" >&2; exit 2 ;;
  *) VERIFY_DIR="$1" run ;;
esac
