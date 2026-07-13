#!/usr/bin/env bash
# shadow-validate-run.sh <stack>
#
# Pilot (#109), validation stage: after audit `gate`, run the LOCAL validator
# model on each audited article and its cited sources, emitting per-claim
# verdicts, then run the deterministic citation-presence gate on each claim and
# structurally coerce a CLEAN-on-uncited to INVALID. Writes one per-batch claim
# file (claim text + source excerpt + local verdict) for the cloud
# validation-verifier to grade. The cloud validator's in-place fixes are
# authoritative and untouched — this only observes, to grade whether the local
# tier is safe to make authoritative for validation.
#
# Mirrors shadow-extract-run.sh: reads the TRANSIENT audit run files
# (dev/audit/dispatch.tsv), which exist after prep and are cleared by `finish`
# — run BETWEEN `audit.sh gate` and `audit.sh finish`. Non-destructive: never
# touches an article, a verdict, or any pipeline state file. Opt-in; the skill
# gates this on STACKS_LOCAL_SHADOW=1.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_ROOT="$(cd "$HERE/../../../.." && pwd)"   # harness -> model-tier -> experiments -> dev -> repo root
INFER="$HERE/local-infer.sh"
GATE="$HERE/claim-citation-gate.sh"
MODEL="${MODEL:-qwen3-30b-a3b-instruct}"
SRC_CAP="${SRC_CAP:-12000}"   # max chars of cited-source text fed per article (num_ctx budget)

# ---------------------------------------------------------------------------
# Pure helpers (self-checkable without a GPU): parse the local model's per-claim
# lines and apply the citation-presence coercion.
# ---------------------------------------------------------------------------

# normalize a raw verdict token to the 5-label rubric (or PARSE-ERROR)
norm_verdict() {
  local v; v=$(printf '%s' "$1" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  case "$v" in
    CLEAN)                              echo CLEAN ;;
    CORRECTION/contradiction)          echo "CORRECTION/contradiction" ;;
    CORRECTION/overstatement)          echo "CORRECTION/overstatement" ;;
    CORRECTION/add-citation)           echo "CORRECTION/add-citation" ;;
    SOFTSPOT)                          echo SOFTSPOT ;;
    CORRECTION*)                       echo "CORRECTION/overstatement" ;;  # bare/unknown subtype -> the safe poison bucket
    *)                                 echo "PARSE-ERROR" ;;
  esac
}

# coerce_verdict <verdict> <claim-text> -> gated verdict
# The harness owns citation-presence: a CLEAN on a claim with no inline [slug]
# citation is structurally invalid (the S24 item-6 miss), so it is coerced to
# INVALID/uncited-clean regardless of what the model returned.
# ponytail: the gate runs on the model's ECHOED claim text, not the source
# article, so a model that alters a citation in its echo can dodge it. Acceptable
# for this advisory shadow; the retrieval follow-on (harness extracts each claim
# from the article and pairs it to its cited source) is what actually closes it.
coerce_verdict() {
  local verdict="$1" claim="$2" gate
  gate=$(bash "$GATE" "$claim")
  if [[ "$gate" == "UNCITED" && "$verdict" == "CLEAN" ]]; then
    echo "INVALID/uncited-clean"
  else
    echo "$verdict"
  fi
}

# parse_and_gate <model-output-file> <out-claim-file> -> emits, per claim line,
# the gated tuple; returns the claim count on stdout. Each model line is
# "<verdict> ||| <claim text> ||| <source excerpt or NONE>".
parse_and_gate() {
  local infile="$1" outfile="$2" n=0
  while IFS= read -r line; do
    [[ "$line" == *"|||"* ]] || continue
    local raw_v claim excerpt v
    raw_v="${line%%|||*}"
    local rest="${line#*|||}"
    claim="${rest%%|||*}"
    excerpt="${rest#*|||}"
    claim=$(printf '%s' "$claim" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    excerpt=$(printf '%s' "$excerpt" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    [[ -n "$claim" ]] || continue
    v=$(norm_verdict "$raw_v")
    v=$(coerce_verdict "$v" "$claim")
    n=$((n+1))
    { printf '### Claim %d\n' "$n"
      printf 'Claim: %s\n' "$claim"
      printf 'Source excerpt (local-quoted): %s\n' "${excerpt:-NONE}"
      printf 'Local verdict: %s\n\n' "$v"
    } >> "$outfile"
  done < "$infile"
  echo "$n"
}

# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--self-check" ]]; then
  work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
  cat > "$work/model.txt" <<'EOF'
CLEAN ||| GPT-4 judges reach over 80% agreement with humans. [arxiv-2306.05685] ||| strong LLM judges like GPT-4 achieve over 80% agreement
CORRECTION/overstatement ||| GPT-4 consistently outperforms human raters. [arxiv-2306.05685] ||| can match human preferences well
CLEAN ||| Cox Automotive runs continuous red teaming throughout its lifecycle. ||| Continuous red teaming integrated throughout development lifecycle
noise line with no delimiter, must be skipped
SOFTSPOT ||| Most teams find a two-week shadow window sufficient. ||| no cited source states any window length
EOF
  got=$(parse_and_gate "$work/model.txt" "$work/out.txt")
  fail=0
  [[ "$got" == "4" ]] || { echo "FAIL: expected 4 claims parsed, got $got"; fail=1; }
  # claim 1: cited + CLEAN -> stays CLEAN
  grep -q "Local verdict: CLEAN" "$work/out.txt" || { echo "FAIL: cited CLEAN not preserved"; fail=1; }
  # claim 2: cited + overstatement -> stays
  grep -q "Local verdict: CORRECTION/overstatement" "$work/out.txt" || { echo "FAIL: overstatement not preserved"; fail=1; }
  # claim 3: UNCITED + CLEAN -> coerced to INVALID (the item-6 structural close)
  grep -q "Local verdict: INVALID/uncited-clean" "$work/out.txt" || { echo "FAIL: uncited-CLEAN not coerced to INVALID"; fail=1; }
  # claim 4: uncited + SOFTSPOT -> stays SOFTSPOT (not coerced; only CLEAN is)
  grep -q "Local verdict: SOFTSPOT" "$work/out.txt" || { echo "FAIL: uncited SOFTSPOT wrongly altered"; fail=1; }
  if [[ $fail -eq 0 ]]; then echo "SELF-CHECK PASS"; else echo "SELF-CHECK FAIL"; exit 1; fi
  exit 0
fi

STACK="${1:?Usage: shadow-validate-run.sh <stack> | --self-check}"

# Reset the output FIRST, before any failable check below. If resolve/cd/dispatch
# fails we exit with an EMPTY manifest, never leaving a previous run's batches for
# the skill's verifier to re-grade as if fresh.
OUT="$STACKS_ROOT/dev/experiments/model-tier/live-diffs/validate"
rm -rf "$OUT"; mkdir -p "$OUT"
BATCHES="$OUT/batches.tsv"   # batch_tag<TAB>batchfile — the verifier dispatch manifest
: > "$BATCHES"

LIB="$(bash "$STACKS_ROOT/scripts/resolve-library.sh")" || { echo "ERROR: could not resolve library" >&2; exit 1; }
cd "$LIB" || { echo "ERROR: cannot cd into library: $LIB" >&2; exit 1; }
DEV="$STACK/dev/audit"
DISPATCH="$DEV/dispatch.tsv"
[[ -f "$DISPATCH" ]] || { echo "ERROR: no $DISPATCH — run audit through prep+gate first (finish clears it)" >&2; exit 1; }

# Resolve an article's cited source files from its `sources:` frontmatter list
# (paths are relative to the stack root, e.g. sources/pub/slug.md) and cat them
# into stdout under a PER-SOURCE cap. A single total `head -c` let the first
# (often largest) source consume the whole budget, feeding the model zero bytes
# of the later cited sources — so the model looked like it mis-retrieved a claim
# whose source text the harness had actually withheld. Splitting SRC_CAP evenly
# guarantees every cited source is represented. Missing source files are logged.
cited_sources_text() {
  local art="$1"
  local rels=()
  while IFS= read -r rel; do rels+=("$rel"); done < <(
    awk '/^---$/{c++; next} c==1 && /^[[:space:]]*-[[:space:]]*sources\//{sub(/^[[:space:]]*-[[:space:]]*/,""); print} c>=2{exit}' "$art"
  )
  local n=${#rels[@]}
  [[ $n -gt 0 ]] || return 0
  local per=$(( SRC_CAP / n )); [[ $per -lt 1 ]] && per=1
  local rel f
  for rel in "${rels[@]}"; do
    f="$STACK/$rel"
    if [[ ! -f "$f" ]]; then echo "MISSING-SOURCE $rel (article $(basename "$art"))" >&2; continue; fi
    printf '\n===== SOURCE: %s =====\n' "$(basename "$rel")"
    head -c "$per" "$f"
    printf '\n'
  done
}

validate_prompt() { # <article-file> -> stdout: the local per-claim validation prompt
  local art="$1"
  cat <<EOF
You validate a knowledge-wiki ARTICLE against its cited SOURCES. For every
factual claim the article makes, judge it against the source that grounds it and
assign ONE verdict:
  CLEAN                      - the claim is fully supported by its cited source
  CORRECTION/contradiction   - the source states the OPPOSITE of the claim
  CORRECTION/overstatement   - the claim is stronger/broader than the source supports
  CORRECTION/add-citation    - the claim is true and a listed source grounds it, but it carries no inline citation
  SOFTSPOT                   - no cited or listed source states this claim at all
Be CONSERVATIVE: do not invent claims, do not flag a supported claim, quote the
exact source phrase you judged against.
OUTPUT: one line per claim, EXACTLY this shape, nothing else:
<verdict> ||| <claim text> ||| <source phrase you judged against, or NONE>

ARTICLE:
$(cat "$art")

CITED SOURCES:
$(cited_sources_text "$art")

OUTPUT: one line per claim as specified. Nothing else.
EOF
}

n=0 skipped=0 failed=0 total_claims=0 unparsed=0
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# group articles by batch_tag so each batch file feeds one verifier agent
while IFS=$'\t' read -r batch_tag slug art; do
  [[ -n "${art:-}" ]] || continue
  batchfile="$OUT/batch-${batch_tag}.md"
  if [[ ! -f "$batchfile" ]]; then
    printf '# Validation shadow batch %s — stack %s (model %s)\n\n' "$batch_tag" "$STACK" "$MODEL" > "$batchfile"
    printf '%s\t%s\n' "$batch_tag" "$batchfile" >> "$BATCHES"
  fi
  if [[ ! -f "$art" ]]; then echo "SKIP $batch_tag/$slug: no article ($art)" >&2; skipped=$((skipped+1)); continue; fi
  printf '## Article: %s\n\n' "$slug" >> "$batchfile"
  validate_prompt "$art" > "$work/prompt.txt"
  if ! NUM_CTX="${NUM_CTX:-16384}" bash "$INFER" "$MODEL" "$work/prompt.txt" "$work/out.txt" 2>"$work/err"; then
    echo "VALIDATE-FAIL $batch_tag/$slug ($(tail -1 "$work/err" 2>/dev/null))" >&2; failed=$((failed+1)); continue
  fi
  claims=$(parse_and_gate "$work/out.txt" "$batchfile")
  # A 0-claim article is NOT clean coverage — the model emitted nothing parseable
  # (or silently dropped every claim). Flag it so the verifier metrics are not
  # inflated by articles the local model simply skipped.
  if [[ "$claims" -eq 0 ]]; then
    echo "UNPARSED $batch_tag/$slug: local model emitted 0 parseable claim lines" >&2
    printf 'Local verdict: UNPARSED (0 claim lines emitted)\n\n' >> "$batchfile"
    unparsed=$((unparsed+1))
  fi
  total_claims=$((total_claims+claims))
  n=$((n+1))
done < "$DISPATCH"

echo "SHADOW_VALIDATE_SUMMARY: stack=$STACK model=$MODEL articles=$n skipped=$skipped failed=$failed unparsed=$unparsed claims=$total_claims batches=$(wc -l < "$BATCHES" | tr -d ' ') -> $OUT" >&2
