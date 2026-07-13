#!/usr/bin/env bash
# shadow-validate-run.sh <stack> | --gold-check | --self-check
#
# Pilot (#109), validation stage — RETRIEVAL build (the follow-on to the confounded
# article-dump version). The harness owns retrieval: `pair-claims.py` splits each
# audited article into claims and, for each, pulls the best token-overlap excerpt
# from that claim's OWN cited source (or, for an uncited claim, its best-matching
# listed source). The local model then judges ONE claim + ONE excerpt with the
# validation-benchmark gate-first prompt — the offline shape that scored 1.00.
#
# Why the rewrite: the previous version dumped the whole article + all sources and
# let the model pick its own excerpt per claim; it re-used one boilerplate passage
# across claims (a retrieval failure) and — with a total source-cap — was fed zero
# bytes of the later cited sources. Both are gone: retrieval is deterministic and
# per-claim, and the uncited-CLEAN coercion now keys on pair-claims' ground-truth
# `cited` flag, not the model's echoed claim text.
#
# Mirrors the run window: reads the TRANSIENT audit dispatch (dev/audit/dispatch.tsv),
# present after `gate`, cleared by `finish`. Non-destructive, opt-in (skill gates on
# STACKS_LOCAL_SHADOW=1). `--gold-check` scores the 7 benchmark items end-to-end
# (ground-truthed, GPU-only) to prove automated pairing reproduces the offline floors.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_ROOT="$(cd "$HERE/../../../.." && pwd)"
INFER="$HERE/local-infer.sh"
PAIR="$HERE/pair-claims.py"
MODEL="${MODEL:-qwen3-30b-a3b-instruct}"
NUM_CTX="${NUM_CTX:-4096}"   # one claim + one excerpt is small; keep ctx tight = fast

# --------------------------------------------------------------------------- #
# Pure helpers (GPU-free, self-checked).                                       #
# --------------------------------------------------------------------------- #

# normalize a model verdict line's leading token to the 5-label rubric.
norm_verdict() {
  local v; v=$(printf '%s' "$1" | tr -d '\r' | sed -E 's/[[:space:]]+$//; s/^[[:space:]]+//')
  case "$v" in
    CLEAN*)                     echo CLEAN ;;
    CORRECTION/contradiction*)  echo "CORRECTION/contradiction" ;;
    CORRECTION/overstatement*)  echo "CORRECTION/overstatement" ;;
    CORRECTION/add-citation*)   echo "CORRECTION/add-citation" ;;
    SOFTSPOT*)                  echo SOFTSPOT ;;
    CORRECTION*)                echo "CORRECTION/overstatement" ;;  # bare/unknown -> safe poison bucket
    *)                          echo "PARSE-ERROR" ;;
  esac
}

# classify <model-verdict-line> <cited 0|1> -> "<verdict>\t<replacement>"
# The uncited-CLEAN coercion (item-6 close) keys on the HARNESS's ground-truth
# `cited` flag from pair-claims, never the model's echoed text — so it can't be
# dodged by the model altering a citation in its output.
classify() {
  local line="$1" cited="$2" head repl="" v
  head="${line%%|*}"
  [[ "$line" == *"|"* ]] && repl=$(printf '%s' "${line#*|}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  v=$(norm_verdict "$head")
  [[ "$cited" == "0" && "$v" == "CLEAN" ]] && v="INVALID/uncited-clean"
  printf '%s\t%s' "$v" "$repl"
}

# gate-first prompt (validation-benchmark.md, verbatim STEP 1/STEP 2) for ONE claim.
gatefirst_prompt() { # <claim> <excerpt> <cited 0|1> <sources-csv>
  cat <<EOF
You are a knowledge validator. You are given ONE article claim and the CITED SOURCE
EXCERPT it rests on (plus the article's frontmatter \`sources:\` list).

Decide in TWO steps — the first gate is whether the claim carries its OWN inline
[source-slug] citation. Do not skip it: an uncited claim is NEVER CLEAN, even when it is
true, because a true-but-uncited claim still needs its citation added.

STEP 1 — does the claim carry an inline [source-slug] citation of its own?

  IF YES (inline-cited):
    - Source supports the claim as stated .............. CLEAN
    - Source states something DIFFERENT (a different
      figure, a reversed direction) ................... CORRECTION/contradiction | {corrected text}
    - Source covers the topic but the claim says MORE
      than it states (added mechanism, rationale
      "because…", invented number, or a generalization
      like "consistently"/"outperforms"/"eliminates"/
      "any"/"zero") .................................... CORRECTION/overstatement | {trimmed text}

  IF NO (no inline citation) — you may NOT return CLEAN:
    - A source already in the article's \`sources:\` list
      states it ....................................... CORRECTION/add-citation | {source-slug to add}
    - No source (cited or listed) states it ........... SOFTSPOT (leave text, flag it;
                                                         never invent a citation or fix)

Do NOT rewrite for wording, tone, or style — only for the defects above.
OUTPUT one line, exactly one of:
  CLEAN
  CORRECTION/contradiction | {corrected claim text}
  CORRECTION/overstatement | {trimmed claim text}
  CORRECTION/add-citation  | {source-slug to add}
  SOFTSPOT

CLAIM: $1

CITED SOURCE EXCERPT: $2

ARTICLE \`sources:\` list: $4

OUTPUT one line as specified. Nothing else.
EOF
}

# judge_claim <claim> <excerpt> <cited> <sources-csv> -> "<verdict>\t<replacement>"
# (impure: one model call). $work must be set.
judge_claim() {
  gatefirst_prompt "$1" "$2" "$3" "$4" > "$work/p.txt"
  if ! NUM_CTX="$NUM_CTX" bash "$INFER" "$MODEL" "$work/p.txt" "$work/o.txt" 2>"$work/e.txt"; then
    printf 'PARSE-ERROR\t\n'; return 0
  fi
  local line; line=$(grep -m1 -iE '^(CLEAN|CORRECTION|SOFTSPOT)' "$work/o.txt" || true)
  [[ -n "$line" ]] || { printf 'PARSE-ERROR\t\n'; return 0; }
  classify "$line" "$3"; printf '\n'   # trailing newline so the consuming `read` returns 0
}

# --------------------------------------------------------------------------- #
if [[ "${1:-}" == "--self-check" ]]; then
  fail=0
  eq() { [[ "$1" == "$2" ]] || { echo "FAIL: '$3' -> '$1' want '$2'"; fail=1; }; }
  eq "$(norm_verdict 'CORRECTION/overstatement | trimmed')" "CORRECTION/overstatement" norm1
  eq "$(norm_verdict 'CLEAN')" "CLEAN" norm2
  eq "$(norm_verdict 'garbage line')" "PARSE-ERROR" norm3
  eq "$(classify 'CLEAN' 1)" $'CLEAN\t' cited-clean
  eq "$(classify 'CLEAN' 0)" $'INVALID/uncited-clean\t' uncited-clean-coerced
  eq "$(classify 'CORRECTION/overstatement | GPT-4 matches humans' 1)" $'CORRECTION/overstatement\tGPT-4 matches humans' repl
  eq "$(classify 'SOFTSPOT' 0)" $'SOFTSPOT\t' softspot
  python3 "$PAIR" --self-check >/dev/null || { echo "FAIL: pair-claims self-check"; fail=1; }
  [[ $fail -eq 0 ]] && echo "SELF-CHECK PASS" || { echo "SELF-CHECK FAIL"; exit 1; }
  exit 0
fi

# --------------------------------------------------------------------------- #
# --gold-check: the 7 validation-benchmark items, end-to-end, ground-truthed.  #
# --------------------------------------------------------------------------- #
if [[ "${1:-}" == "--gold-check" ]]; then
  LIB="$(bash "$STACKS_ROOT/scripts/resolve-library.sh")" || { echo "ERROR: no library" >&2; exit 1; }
  SRC="$LIB/llm/sources"
  [[ -d "$SRC" ]] || { echo "ERROR: gold-check needs the llm stack sources at $SRC" >&2; exit 1; }
  work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
  ARX="$SRC/arxiv/arxiv-2306.05685-llm-as-judge-mt-bench.md"
  ZEN="$SRC/zenml/zenml-2025-12-llmops-1200-deployments.md"
  EVI="$SRC/evidentlyai/evidentlyai-llm-as-a-judge-guide.md"

  # item: gold<TAB>cited<TAB>role<TAB>sources-csv<TAB>src-files(space)<TAB>claim
  #  role: poison{2,3,5} | clean{1,4} | addcite{6} | softspot{7}
  items=(
"CLEAN	1	clean	arxiv-2306.05685-llm-as-judge-mt-bench	$ARX	GPT-4 acting as judge reaches over 80% agreement with human preferences, the same level of agreement seen between two human raters. [arxiv-2306.05685-llm-as-judge-mt-bench]"
"CORRECTION/overstatement	1	poison	arxiv-2306.05685-llm-as-judge-mt-bench	$ARX	GPT-4 acting as judge consistently outperforms human raters on open-ended evaluation. [arxiv-2306.05685-llm-as-judge-mt-bench]"
"CORRECTION/contradiction	1	poison	arxiv-2306.05685-llm-as-judge-mt-bench	$ARX	The authors publicly released MT-bench questions, roughly 300 expert votes, and 30,000 conversations. [arxiv-2306.05685-llm-as-judge-mt-bench]"
"CLEAN	1	clean	arxiv-2306.05685-llm-as-judge-mt-bench	$ARX	The paper documents three judge biases — position bias (favoring the first answer shown), verbosity bias (favoring longer answers), and self-enhancement bias (a judge favoring its own outputs). [arxiv-2306.05685-llm-as-judge-mt-bench]"
"CORRECTION/overstatement	1	poison	zenml-2025-12-llmops-1200-deployments	$ZEN	Shadow mode lets a team deploy any new agent live with zero risk. [zenml-2025-12-llmops-1200-deployments]"
"CORRECTION/add-citation	0	addcite	zenml-2025-12-llmops-1200-deployments,evidentlyai-llm-as-a-judge-guide	$ZEN $EVI	Cox Automotive runs continuous red teaming throughout its development lifecycle, not as a one-time pre-launch assessment."
"SOFTSPOT	0	softspot	zenml-2025-12-llmops-1200-deployments,evidentlyai-llm-as-a-judge-guide	$ZEN $EVI	In practice, most teams find a two-week shadow-mode window sufficient before enabling live execution."
  )
  poison_total=0 poison_caught=0 fc=0 exact=0 i=0
  printf '# Validation gold-check (model %s) — automated pairing vs offline gold\n\n' "$MODEL"
  for row in "${items[@]}"; do
    i=$((i+1))
    IFS=$'\t' read -r gold cited role csv srcfiles claim <<<"$row"
    excerpt=$(printf '%s' "$claim" | python3 "$PAIR" --retrieve $srcfiles || true)
    IFS=$'\t' read -r verdict repl < <(judge_claim "$claim" "$excerpt" "$cited" "$csv") || true
    [[ "$verdict" == "$gold" ]] && exact=$((exact+1))
    local_pass="—"
    case "$role" in
      poison)   poison_total=$((poison_total+1)); [[ "$verdict" == CORRECTION/* ]] && { poison_caught=$((poison_caught+1)); local_pass=CAUGHT; } || local_pass="MISS(poison shipped)";;
      clean)    [[ "$verdict" == CORRECTION/* ]] && { fc=$((fc+1)); local_pass="FALSE-CORRECTION"; } || local_pass=ok;;
      addcite)  [[ "$verdict" == "CORRECTION/add-citation" ]] && local_pass=ok || { [[ "$verdict" == CORRECTION/overstatement || "$verdict" == CORRECTION/contradiction ]] && { fc=$((fc+1)); local_pass="FALSE-CORRECTION(trimmed)"; } || local_pass="under-action($verdict)"; };;
      softspot) [[ "$verdict" == "SOFTSPOT" ]] && local_pass=ok || { [[ "$verdict" == CORRECTION/* ]] && { fc=$((fc+1)); local_pass="FALSE-CORRECTION"; } || local_pass="$verdict"; };;
    esac
    printf 'item %d [%s]  gold=%-26s got=%-26s %s\n' "$i" "$role" "$gold" "$verdict" "$local_pass"
    [[ -n "$repl" ]] && printf '        replacement: %s\n' "$repl"
  done
  echo
  printf 'POISON RECALL = %d/%d   FALSE-CORRECTIONS = %d/4   EXACT-ACTION = %d/7   (floors: recall>=0.90, fc=0)\n' \
    "$poison_caught" "$poison_total" "$fc" "$exact"
  exit 0
fi

# --------------------------------------------------------------------------- #
# Live run over a stack's audit dispatch.                                      #
# --------------------------------------------------------------------------- #
STACK="${1:?Usage: shadow-validate-run.sh <stack> | --gold-check | --self-check}"

# Reset output FIRST, before any failable check, so an early exit never leaves a
# stale manifest for the verifier to re-grade.
OUT="$STACKS_ROOT/dev/experiments/model-tier/live-diffs/validate"
rm -rf "$OUT"; mkdir -p "$OUT"
BATCHES="$OUT/batches.tsv"
: > "$BATCHES"

LIB="$(bash "$STACKS_ROOT/scripts/resolve-library.sh")" || { echo "ERROR: could not resolve library" >&2; exit 1; }
cd "$LIB" || { echo "ERROR: cannot cd into library: $LIB" >&2; exit 1; }
DISPATCH="$STACK/dev/audit/dispatch.tsv"
[[ -f "$DISPATCH" ]] || { echo "ERROR: no $DISPATCH — run audit through prep+gate first (finish clears it)" >&2; exit 1; }

n=0 skipped=0 total_claims=0 unparsed=0 corrections=0
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

while IFS=$'\t' read -r batch_tag slug art; do
  [[ -n "${art:-}" ]] || continue
  batchfile="$OUT/batch-${batch_tag}.md"
  if [[ ! -f "$batchfile" ]]; then
    printf '# Validation shadow batch %s — stack %s (model %s, retrieval build)\n\n' "$batch_tag" "$STACK" "$MODEL" > "$batchfile"
    printf '%s\t%s\n' "$batch_tag" "$batchfile" >> "$BATCHES"
  fi
  if [[ ! -f "$art" ]]; then echo "SKIP $batch_tag/$slug: no article ($art)" >&2; skipped=$((skipped+1)); continue; fi
  printf '## Article: %s\n\n' "$slug" >> "$batchfile"

  claims=0
  while IFS=$'\t' read -r idx cited claim cand_slug excerpt; do
    [[ -n "${claim:-}" ]] || continue
    claims=$((claims+1))
    IFS=$'\t' read -r verdict repl < <(judge_claim "$claim" "$excerpt" "$cited" "$cand_slug") || true
    [[ "$verdict" == CORRECTION/* || "$verdict" == INVALID/* ]] && corrections=$((corrections+1))
    { printf '### Claim %d (%s)\n' "$claims" "$([[ "$cited" == 1 ]] && echo "cited:$cand_slug" || echo uncited)"
      printf 'Claim: %s\n' "$claim"
      printf 'Source excerpt (harness-retrieved from %s): %s\n' "$cand_slug" "${excerpt:-NONE}"
      printf 'Local verdict: %s\n' "$verdict"
      [[ -n "$repl" ]] && printf 'Proposed replacement: %s\n' "$repl"
      printf '\n'
    } >> "$batchfile"
  done < <(python3 "$PAIR" "$art" "$STACK")

  if [[ "$claims" -eq 0 ]]; then
    echo "UNPARSED $batch_tag/$slug: pair-claims extracted 0 claims" >&2
    printf 'Local verdict: UNPARSED (0 claims extracted)\n\n' >> "$batchfile"
    unparsed=$((unparsed+1))
  fi
  total_claims=$((total_claims+claims))
  n=$((n+1))
done < "$DISPATCH"

echo "SHADOW_VALIDATE_SUMMARY: stack=$STACK model=$MODEL articles=$n skipped=$skipped unparsed=$unparsed claims=$total_claims corrections=$corrections batches=$(wc -l < "$BATCHES" | tr -d ' ') -> $OUT" >&2
