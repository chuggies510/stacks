#!/usr/bin/env bash
# synth-shadow.sh <concept-block-file> <cloud-article-file|NONE> <item-id>
#
# Local-first, cloud-authoritative pilot for the stacks synthesis stage:
# runs the local model on ONE concept block, tag-postfilters the output,
# captures cheap deterministic structural metrics for local vs cloud, and
# appends one JSON line to live-diffs/synthesis.jsonl for the liminal peer
# session to judge recall/over-claim downstream. This script does NOT judge
# quality — structural metrics only (word count, citation count, tag
# in-vocab count, required-key presence).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MTIER="$(cd "$HERE/.." && pwd)"
LIVE_DIFFS="$MTIER/live-diffs"
BENCH="$MTIER/synthesis-benchmark.md"
INFER="$HERE/local-infer.sh"
POSTFILTER="$HERE/tag-postfilter.sh"
MODEL="${MODEL:-qwen3-30b-a3b-instruct}"
RUN_ID="${RUN_ID:-manual}"
VOCAB="llm llmops evals llm-as-judge rag agents hallucination observability shadow-mode context-engineering prompt-engineering guardrails memory mcp multi-agent cost-economics fine-tuning"

concept_file="${1:?Usage: synth-shadow.sh <concept-block-file> <cloud-article-file|NONE> <item-id>}"
cloud_file="${2:?}"
item_id="${3:?}"
[[ -f "$concept_file" ]] || { echo "ERROR: concept block not found: $concept_file" >&2; exit 1; }

mkdir -p "$LIVE_DIFFS/bodies"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

in_vocab() { local t="$1" v; for v in $VOCAB; do [[ "$t" == "$v" ]] && return 0; done; return 1; }

# metrics_for <file> -> "words citations tags_total tags_in_vocab has_title has_last_verified has_sources has_routing"
metrics_for() {
  local f="$1" fm body words cites tags_total=0 tags_ok=0 in_list=0 t
  fm=$(awk '/^---$/{c++; if(c==2) exit; next} c==1' "$f")
  body=$(awk 'BEGIN{c=0} /^---$/{c++; next} c>=2' "$f")
  words=$(wc -w <<< "$body" | tr -d ' ')
  cites=$(sed -E 's/\[\[[^]]*\]\]//g' <<< "$body" | grep -oE '\[[a-zA-Z0-9][a-zA-Z0-9._-]*\]' | wc -l | tr -d ' ')
  while IFS= read -r line; do
    if [[ "$line" =~ ^tags:[[:space:]]*\[(.*)\]$ ]]; then
      IFS=',' read -ra arr <<< "${BASH_REMATCH[1]}"
      for t in "${arr[@]}"; do t="$(echo "$t" | xargs)"; [[ -z "$t" ]] && continue
        tags_total=$((tags_total+1)); in_vocab "$t" && tags_ok=$((tags_ok+1)); done
    elif [[ "$line" == "tags:" ]]; then in_list=1
    elif [[ $in_list -eq 1 && "$line" =~ ^[[:space:]]*-[[:space:]]*(.+)$ ]]; then
      t="$(echo "${BASH_REMATCH[1]}" | xargs)"; tags_total=$((tags_total+1)); in_vocab "$t" && tags_ok=$((tags_ok+1))
    else in_list=0
    fi
  done <<< "$fm"
  local ht=false hlv=false hs=false hr=false
  grep -qE '^title:' <<< "$fm" && ht=true
  grep -qE '^last_verified:' <<< "$fm" && hlv=true
  grep -qE '^sources:' <<< "$fm" && hs=true
  grep -qE '^routing:' <<< "$fm" && hr=true
  echo "$words $cites $tags_total $tags_ok $ht $hlv $hs $hr"
}

json_for() { # <words> <cites> <tt> <to> <ht> <hlv> <hs> <hr> <rel-path>
  jq -n --argjson words "$1" --argjson citations "$2" --argjson tags_total "$3" --argjson tags_in_vocab "$4" \
    --argjson has_title "$5" --argjson has_last_verified "$6" --argjson has_sources "$7" --argjson has_routing "$8" \
    --arg body_path "$9" \
    '{words:$words, citations:$citations, tags_total:$tags_total, tags_in_vocab:$tags_in_vocab,
      has_title:$has_title, has_last_verified:$has_last_verified, has_sources:$has_sources, has_routing:$has_routing,
      body_path:$body_path}'
}

# Assemble prompt: verbatim rubric (lines 17-41) + tag vocab (lines 46-48) + concept block
sed -n '17,41p' "$BENCH" > "$work/prompt.txt"
{ echo; echo "Allowed tags:"; sed -n '46,48p' "$BENCH"; echo; cat "$concept_file"; } >> "$work/prompt.txt"

localraw="$work/local_raw.md"
t0=$(date +%s.%N)
if ! bash "$INFER" "$MODEL" "$work/prompt.txt" "$localraw" 2>"$work/local.err"; then
  echo "FAIL item=$item_id: local inference errored (see $work/local.err, printed below)" >&2
  cat "$work/local.err" >&2
  jq -nc --arg item "$item_id" --arg model "$MODEL" --arg run "$RUN_ID" \
    '{item:$item, model:$model, run_id:$run, status:"local-inference-failed"}' >> "$LIVE_DIFFS/synthesis.jsonl"
  exit 1
fi
t1=$(date +%s.%N)
sed -i -E '1{/^```/d}; ${/^```$/d}' "$localraw"   # strip an outer code fence, if the model added one

echo "--- tags before filter (item=$item_id) ---" >&2
grep -A6 '^tags:' "$localraw" >&2 || echo "(no tags: line found)" >&2

local_body="$LIVE_DIFFS/bodies/${item_id}__local.md"
cp "$localraw" "$local_body"
bash "$POSTFILTER" "$local_body"

echo "--- tags after filter (item=$item_id) ---" >&2
grep -A6 '^tags:' "$local_body" >&2 || echo "(no tags: line found)" >&2

words_local=$(wc -w < "$local_body" | tr -d ' ')
toksec_est=$(awk -v w="$words_local" -v t0="$t0" -v t1="$t1" 'BEGIN{d=t1-t0; if(d>0) printf "%.1f", (w*1.3)/d; else print "NA"}')

read -r w_l c_l tt_l to_l ht_l hlv_l hs_l hr_l <<< "$(metrics_for "$local_body")"
local_json=$(json_for "$w_l" "$c_l" "$tt_l" "$to_l" "$ht_l" "$hlv_l" "$hs_l" "$hr_l" "live-diffs/bodies/${item_id}__local.md")

cloud_json="null"
if [[ "$cloud_file" != "NONE" && -f "$cloud_file" ]]; then
  cloud_body="$LIVE_DIFFS/bodies/${item_id}__cloud.md"
  cp "$cloud_file" "$cloud_body"
  read -r w_c c_c tt_c to_c ht_c hlv_c hs_c hr_c <<< "$(metrics_for "$cloud_body")"
  cloud_json=$(json_for "$w_c" "$c_c" "$tt_c" "$to_c" "$ht_c" "$hlv_c" "$hs_c" "$hr_c" "live-diffs/bodies/${item_id}__cloud.md")
else
  echo "NOTE item=$item_id: no cloud article at '$cloud_file' — logging local metrics only, cloud:null" >&2
fi

jq -nc --arg item "$item_id" --arg model "$MODEL" --arg run "$RUN_ID" --arg toksec "$toksec_est" \
  --argjson local "$local_json" --argjson cloud "$cloud_json" \
  '{item:$item, model:$model, run_id:$run, tok_s_est:$toksec, status:"ok", local:$local, cloud:$cloud}' \
  >> "$LIVE_DIFFS/synthesis.jsonl"

echo "OK item=$item_id: logged to $LIVE_DIFFS/synthesis.jsonl (tok/s est=$toksec_est)" >&2
