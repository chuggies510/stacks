#!/usr/bin/env bash
# extraction-verify-summary.sh <verify-dir>
#
# Advisory window (#109): aggregate the per-candidate grade JSONs the
# extraction-verifier wrote (one {slug}.json each) into a single go/no-go read
# on how many local-model NEW/NEAR candidates were actually over-mints (a
# concept an existing article already covers) vs genuine new gaps. Mirrors
# synth-verify-summary.sh: one jq -s pass DERIVING every count from the
# component fields (verdict, is_overmint) — never trusting a hypothetical
# self-reported aggregate. Reads only; decides nothing — the human reads this
# after a real batch and calls the flip.
#
#   bash extraction-verify-summary.sh <verify-dir>
#   bash extraction-verify-summary.sh --self-check
set -euo pipefail

self_check() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  # 4 graded candidates:
  #   a: genuine new gap, verdict NEW, is_overmint correctly false
  #   b: over-mint caught (the agent-rl-fine-tuning worked example) — local
  #      said NEW, verdict flips it to reuse:, is_overmint true
  #   c: NEAR-routed candidate confirmed as a legitimate reuse (over-mint too)
  #   d: INCONSISTENT — the agent wrote is_overmint:false but its own verdict
  #      is a reuse: — the summary must derive over-mint-caught from the
  #      verdict field, NOT trust the (possibly wrong) is_overmint boolean,
  #      else d would be miscounted as a genuine new gap.
  printf '%s\n' '{"slug":"prompt-caching","local_decision":"NEW","prematch":"NEW","verdict":"NEW","is_overmint":false,"reason":"no existing article covers prompt caching mechanics","recall_gaps":[]}' > "$d/a.json"
  printf '%s\n' '{"slug":"agent-rl-fine-tuning","local_decision":"NEW","prematch":"NEW","verdict":"reuse:agent-harness-engineering","is_overmint":true,"reason":"already stated in agent-harness-engineering body (OpenPipe GRPO)","recall_gaps":["source also covers judge-calibration drift, local dropped it entirely"]}' > "$d/b.json"
  printf '%s\n' '{"slug":"token-budget","local_decision":"NEW","prematch":"NEAR:token-budget-management","verdict":"reuse:token-budget-management","is_overmint":true,"reason":"token-budget-management scope line already covers capacity/tokenization budgeting","recall_gaps":[]}' > "$d/c.json"
  printf '%s\n' '{"slug":"guardrail-escalation","local_decision":"NEW","prematch":"NEW","verdict":"reuse:guardrails-infrastructure","is_overmint":false,"reason":"agent mis-set is_overmint despite a reuse verdict — inconsistent record","recall_gaps":[]}' > "$d/d.json"
  # (e) local was ALREADY correct (local_decision reuse:, verifier confirms the
  # same reuse) — this is NOT an over-mint the verifier caught, so it must be
  # excluded from over_mint_caught (codex #109: don't miscredit correct locals).
  printf '%s\n' '{"slug":"cost-budget","local_decision":"reuse:llm-cost-control-production","prematch":"NEAR:llm-cost-control-production","verdict":"reuse:llm-cost-control-production","is_overmint":false,"reason":"local already reused correctly","recall_gaps":[]}' > "$d/e.json"
  # (f) local reused the WRONG article; the verifier CHANGED the target — still an
  # over-mint the verifier caught, even though local_decision already began reuse:
  # (codex #109: the old flipped predicate excluded all reuse: locals and missed this).
  printf '%s\n' '{"slug":"agent-rl","local_decision":"reuse:agent-memory-systems","prematch":"NEW","verdict":"reuse:agent-harness-engineering","is_overmint":true,"reason":"local mis-homed it to memory-systems; belongs in harness-engineering","recall_gaps":[]}' > "$d/f.json"
  local out; out=$(VERIFY_DIR="$d" run 2>&1)
  local fail=0
  grep -q 'graded: 6'                 <<<"$out" || { echo "FAIL: graded count"; fail=1; }
  grep -q 'over-mint caught: 4'        <<<"$out" || { echo "FAIL: over-mint-caught (flips incl changed-target 'f'; agreement 'e' excluded)"; fail=1; }
  grep -q 'genuine new: 1'             <<<"$out" || { echo "FAIL: genuine-new count"; fail=1; }
  grep -q 'recall gaps noted: 1'       <<<"$out" || { echo "FAIL: recall gaps count"; fail=1; }
  grep -q 'go/no-go' <<<"$out"         || { echo "FAIL: missing go/no-go line"; fail=1; }
  if [[ $fail -eq 0 ]]; then echo "SELF-CHECK PASS"; else echo "SELF-CHECK FAIL"; return 1; fi
}

run() {
  local dir="${VERIFY_DIR:?}"
  shopt -s nullglob
  local files=("$dir"/*.json)
  shopt -u nullglob
  [[ ${#files[@]} -gt 0 ]] || { echo "No grade JSONs in $dir — run a batch with the extraction verifier first."; return 1; }

  # Slurp all grade objects; compute the go/no-go aggregates in one jq pass.
  # An over-mint CAUGHT is one the verifier CHANGED: the verdict is a reuse: that
  # DIFFERS from what the local decided — covering both local NEW → reuse: (a
  # missed reuse) and local reuse:wrong-home → reuse:right-home (a mis-targeted
  # reuse). Only a verdict that exactly equals the local's own reuse: decision is
  # an agreement, not a catch, and is excluded (codex #109). Derives from
  # local_decision + verdict, never .is_overmint.
  jq -s '
    def flipped: (.verdict | startswith("reuse:")) and ((.local_decision // "NEW") != .verdict);
    {
      graded:          length,
      over_mint_caught: (map(select(flipped)) | length),
      genuine_new:      (map(select(.verdict == "NEW")) | length),
      recall_gaps:      (map(.recall_gaps // []) | add | length)
    }
    | "graded: \(.graded)\n"
    + "over-mint caught: \(.over_mint_caught)\n"
    + "genuine new: \(.genuine_new)\n"
    + "recall gaps noted: \(.recall_gaps)"
  ' -r "${files[@]}"

  echo "---"
  jq -s -r '
    def flipped: (.verdict | startswith("reuse:")) and ((.local_decision // "NEW") != .verdict);
    (map(select(flipped)) | length) as $caught
    | (map(select(.verdict == "NEW")) | length) as $new
    | ($caught + $new) as $total
    | if $total == 0 then "go/no-go: no routed candidates to grade"
      else "go/no-go: informational — \($caught)/\($total) routed (NEAR/NEW) candidates were over-mints caught before shipping; compare against extraction-benchmark.md local raw mint count for the true catch rate."
      end
  ' "${files[@]}"
}

case "${1:-}" in
  --self-check) self_check ;;
  "") echo "Usage: extraction-verify-summary.sh <verify-dir> | --self-check" >&2; exit 2 ;;
  *) VERIFY_DIR="$1" run ;;
esac
