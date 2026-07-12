#!/usr/bin/env bash
# validator-shadow.sh [model]
#
# Non-destructive proof: runs the stacks `validator` agent's gate-first rubric
# (verbatim, from ../validation-benchmark.md lines 27-58) against the 7-item
# offline gold set, 3 greedy passes, and scores poison recall / false-correction
# rate / determinism. Never touches any article or production file — output
# goes to a scratch dir only.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="${1:-qwen3-30b-a3b-instruct}"
BENCH="$HERE/../validation-benchmark.md"
INFER="$HERE/local-infer.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Verbatim rubric: the fenced block is lines 26-59 of validation-benchmark.md
# (26/59 are the ``` fences; 27-58 is the prompt body).
RUBRIC=$(sed -n '27,58p' "$BENCH")

declare -A GOLD=( [1]="CLEAN" [2]="CORRECTION/overstatement" [3]="CORRECTION/contradiction"
                   [4]="CLEAN" [5]="CORRECTION/overstatement" [6]="CORRECTION/add-citation"
                   [7]="SOFTSPOT" )

GATE_SH="$HERE/claim-citation-gate.sh"

item_block() {
  case "$1" in
    1) cat <<'EOF'
Claim: GPT-4 acting as judge reaches over 80% agreement with human preferences, the same level of agreement seen between two human raters. [arxiv-2306.05685-llm-as-judge-mt-bench]
Source excerpt: "strong LLM judges like GPT-4 can match both controlled and crowdsourced human preferences well, achieving over 80% agreement, the same level of agreement between humans."
EOF
    ;;
    2) cat <<'EOF'
Claim: GPT-4 acting as judge consistently outperforms human raters on open-ended evaluation. [arxiv-2306.05685-llm-as-judge-mt-bench]
Source excerpt: "can match both controlled and crowdsourced human preferences well, achieving over 80% agreement, the same level of agreement between humans."
EOF
    ;;
    3) cat <<'EOF'
Claim: The authors publicly released MT-bench questions, roughly 300 expert votes, and 30,000 conversations. [arxiv-2306.05685-llm-as-judge-mt-bench]
Source excerpt: "Public release: MT-bench questions, ~3K expert votes, ~30K conversations."
EOF
    ;;
    4) cat <<'EOF'
Claim: The paper documents three judge biases: position bias (favoring the first answer shown), verbosity bias (favoring longer answers), and self-enhancement bias (a judge favoring its own outputs). [arxiv-2306.05685-llm-as-judge-mt-bench]
Source excerpt: "Known biases: position bias (favoring the first answer shown), verbosity bias (favoring longer answers), and self-enhancement bias (a judge favoring its own outputs); plus limited reasoning ability."
EOF
    ;;
    5) cat <<'EOF'
Claim: Shadow mode lets a team deploy any new agent live with zero risk. [zenml-2025-12-llmops-1200-deployments]
Source excerpt: "Ramp: Runs agents in shadow mode on transactions before live actions; LLM Judge compares predictions to actual outcomes. Only enables live actions once shadow accuracy hits specific threshold."
EOF
    ;;
    6) cat <<'EOF'
Article sources: frontmatter lists [zenml-2025-12-llmops-1200-deployments, evidentlyai-llm-as-a-judge-guide]
Claim (no inline citation): Cox Automotive runs continuous red teaming throughout its development lifecycle, not as a one-time pre-launch assessment.
Source excerpt (zenml-2025-12-llmops-1200-deployments, already listed in sources:): "Cox Automotive: Continuous red teaming (not one-time assessment) integrated throughout development lifecycle."
EOF
    ;;
    7) cat <<'EOF'
Article sources: frontmatter lists [zenml-2025-12-llmops-1200-deployments, evidentlyai-llm-as-a-judge-guide]
Claim (no inline citation): In practice, most teams find a two-week shadow-mode window sufficient before enabling live execution.
Source excerpt: neither listed source states any window length; no cited source covers this claim.
EOF
    ;;
  esac
}

parse_label() {
  # first line of the model reply, up to the leading label token
  head -1 "$1" | tr -d '\r' | grep -oE '^[A-Z]+(/[a-z-]+)?' || echo "PARSE-ERROR"
}

echo "Model: $MODEL"
echo

# --- STEP 1 of the recipe: run the deterministic citation gate on each
# item's claim BEFORE the model ever sees it (#109). The gate decides
# CITED/UNCITED as pure regex, not a model judgment; an UNCITED item gets a
# preamble line telling the model it may not return CLEAN, closing the S24
# item-6 miss structurally rather than hoping the prompt's own STEP 1 holds.
declare -A GATE
for i in 1 2 3 4 5 6 7; do
  claim_text=$(item_block "$i" | sed -n 's/^Claim[^:]*: //p' | head -1)
  GATE[$i]=$(bash "$GATE_SH" "$claim_text")
done

# --- 3 greedy passes over all 7 items ---
for pass in 1 2 3; do
  for i in 1 2 3 4 5 6 7; do
    preamble=""
    if [[ "${GATE[$i]}" == "UNCITED" ]]; then
      preamble="STEP 1 (harness-determined): this claim carries NO inline citation. You may NOT return CLEAN — decide CORRECTION/add-citation or SOFTSPOT only."$'\n\n'
    fi
    { printf '%s' "$preamble"; printf '%s\n\n' "$RUBRIC"; item_block "$i"; printf '\nOUTPUT one line as specified above.\n'; } \
      > "$WORK/prompt_${i}.txt"
    outfile="$WORK/pass${pass}_item${i}.txt"
    if bash "$INFER" "$MODEL" "$WORK/prompt_${i}.txt" "$outfile" 2>"$WORK/pass${pass}_item${i}.err"; then
      label=$(parse_label "$outfile")
    else
      label="ERROR"
    fi
    printf '%s' "$label" > "$WORK/label_${pass}_${i}.txt"
    echo "pass $pass item $i -> $label" >&2
  done
done

# --- score pass 1 against gold ---
declare -A L1
for i in 1 2 3 4 5 6 7; do L1[$i]=$(cat "$WORK/label_1_${i}.txt"); done

poison_caught=0
for i in 2 3 5; do
  [[ "${L1[$i]}" == CORRECTION* ]] && poison_caught=$((poison_caught+1))
done
poison_recall=$(awk -v c="$poison_caught" 'BEGIN{printf "%.2f", c/3}')

false_corrections=0
item6_note="add-citation caught correctly"
[[ "${L1[1]}" != "CLEAN" ]] && false_corrections=$((false_corrections+1))
[[ "${L1[4]}" != "CLEAN" ]] && false_corrections=$((false_corrections+1))
case "${L1[6]}" in
  CORRECTION/overstatement|CORRECTION/contradiction)
    false_corrections=$((false_corrections+1))
    item6_note="FALSE CORRECTION: reworded instead of only adding citation"
    ;;
  CLEAN)
    item6_note="MISS (S24 signature): returned CLEAN, add-citation not applied (not a floor breach per benchmark note)"
    ;;
  CORRECTION/add-citation) item6_note="add-citation caught correctly (gate-first prompt closed the S24 miss)" ;;
  SOFTSPOT) item6_note="mis-flagged as SOFTSPOT (should be add-citation)" ;;
esac
[[ "${L1[7]}" == CORRECTION* ]] && false_corrections=$((false_corrections+1))
false_correction_rate=$(awk -v f="$false_corrections" 'BEGIN{printf "%.2f", f/4}')

echo
echo "=== Per-item verdict (pass 1) vs gold ==="
printf '%-4s %-28s %-28s %s\n' "Item" "Gold" "Model verdict" "Match"
for i in 1 2 3 4 5 6 7; do
  match="NO"
  [[ "${L1[$i]}" == "${GOLD[$i]}" ]] && match="YES"
  printf '%-4s %-28s %-28s %s\n' "$i" "${GOLD[$i]}" "${L1[$i]}" "$match"
done

echo
echo "=== Determinism (label across 3 passes) ==="
det_all=1
for i in 1 2 3 4 5 6 7; do
  a=$(cat "$WORK/label_1_${i}.txt"); b=$(cat "$WORK/label_2_${i}.txt"); c=$(cat "$WORK/label_3_${i}.txt")
  same="YES"
  if [[ "$a" != "$b" || "$b" != "$c" ]]; then same="NO"; det_all=0; fi
  printf 'item %d: pass1=%s pass2=%s pass3=%s identical=%s\n' "$i" "$a" "$b" "$c" "$same"
done

echo
echo "=== Metrics ==="
echo "Poison recall (items 2,3,5, floor >=0.90): $poison_recall ($poison_caught/3 caught as CORRECTION)"
echo "False-correction rate (items 1,4,6,7, floor ==0): $false_correction_rate ($false_corrections/4)"
echo "Item 6 (add-citation) note: $item6_note"
echo "Determinism across 3 greedy passes (all 7 items byte-identical label): $([[ $det_all -eq 1 ]] && echo YES || echo NO)"
