#!/usr/bin/env bash
# shadow-enrich-run.sh <stack>
#
# Pilot (#109), enrichment stage: for each audit gap, run the LOCAL enrichment
# loop entirely in the harness — Brave web search -> curl fetch (fetch-source-
# text.sh) -> LOCAL model grounding judgment + tier. The deterministic
# url-dedup-gate owns the DUP decision (set membership, no model), the local
# model owns the ONE object judgment (does this fetched passage STATE the gap's
# claim, at what tier). Writes a per-candidate manifest for the cloud
# enrichment-verifier to grade. The cloud enrichment agent's staged sources are
# authoritative and untouched — this only observes, to grade whether the local
# loop is safe to make authoritative for enrichment.
#
# The LOCAL model NEVER drives the tools (local models are unreliable at native
# tool-calling): the harness does the Brave search + fetch, the model judges only
# the fetched text. Matches the recipe (DESIGN-local-tier.md): harness owns every
# meta-decision (which queries, dedup), model owns the single grounding judgment.
#
# Mirrors shadow-extract-run.sh: reads the TRANSIENT enrich run files
# (dev/enrich/dispatch.tsv), which exist after prep and are cleared by `finish`
# — run BETWEEN `enrich.sh gate` and `enrich.sh finish`. Non-destructive: never
# stages a source or touches any pipeline state file. Opt-in; the skill gates
# this on STACKS_LOCAL_SHADOW=1.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_ROOT="$(cd "$HERE/../../../.." && pwd)"   # harness -> model-tier -> experiments -> dev -> repo root
INFER="$HERE/local-infer.sh"
DEDUP="$HERE/url-dedup-gate.sh"
FETCH="$STACKS_ROOT/scripts/fetch-source-text.sh"
MODEL="${MODEL:-qwen3-30b-a3b-instruct}"
N_RESULTS="${N_RESULTS:-3}"       # Brave candidates fetched per gap
FETCH_WORDS="${FETCH_WORDS:-1200}" # page-text cap fed to the local judge
BRAVE_KEY_FILE="${BRAVE_KEY_FILE:-$HOME/.config/brave-search.key}"

# ---------------------------------------------------------------------------
# Pure helper (self-checkable without net/GPU): map the local judge's line to a
# staging verdict. Line shape: "<GROUNDED|NOTGROUNDED> ||| tier:<N> ||| <excerpt>".
# GROUNDED + tier 1-3 -> CANDIDATE; GROUNDED + tier 4 -> WEAK; else NOTGROUNDED.
# ---------------------------------------------------------------------------
judge_to_verdict() { # <judge-line> -> "<VERDICT>\t<tier>\t<excerpt>\n"
  local line="$1" g tier excerpt
  # Normalize the verdict token to letters only, uppercased — the model often
  # echoes the prompt template literally as "<GROUNDED>" (angle brackets) or adds
  # punctuation, so strip everything non-alpha rather than exact-match. NOTGROUNDED
  # CONTAINS "GROUNDED" as a substring, so test the negative FIRST.
  g="${line%%|||*}"; g=$(printf '%s' "$g" | tr -cd '[:alpha:]' | tr a-z A-Z)
  local rest="${line#*|||}"
  local tierfield="${rest%%|||*}"
  excerpt="${rest#*|||}"
  tier=$(printf '%s' "$tierfield" | grep -oE '[1-4]' | head -1)
  excerpt=$(printf '%s' "$excerpt" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  # Test every negated form FIRST — each CONTAINS "GROUNDED" as a substring, so a
  # bare *GROUNDED* match would fail OPEN on them (UNGROUNDED/NON-GROUNDED ->
  # letters-only -> UNGROUNDED / NONGROUNDED).
  if [[ "$g" == *NOTGROUNDED* || "$g" == *UNGROUND* || "$g" == *NONGROUND* ]]; then
    printf 'NOTGROUNDED\t\t\n'
  elif [[ "$g" == *GROUNDED* ]]; then
    case "$tier" in
      1|2|3) printf 'CANDIDATE\t%s\t%s\n' "$tier" "$excerpt" ;;
      4)     printf 'WEAK\t4\t%s\n' "$excerpt" ;;
      *)     printf 'CANDIDATE\t3\t%s\n' "$excerpt" ;;  # grounded but no clean tier -> default mid, verifier re-tiers
    esac
  else
    printf 'NOTGROUNDED\t\t\n'   # unparseable verdict -> fail-closed to not-grounded
  fi
}

if [[ "${1:-}" == "--self-check" ]]; then
  fail=0
  chk() { local got; got=$(judge_to_verdict "$1"); [[ "$got" == "$2" ]] || { echo "FAIL: '$1' -> '$got' want '$2'"; fail=1; }; }
  chk "GROUNDED ||| tier:2 ||| over 80% agreement with humans"  $'CANDIDATE\t2\tover 80% agreement with humans'
  chk "GROUNDED ||| tier:4 ||| a reddit thread says so"          $'WEAK\t4\ta reddit thread says so'
  chk "NOTGROUNDED ||| ||| "                                     $'NOTGROUNDED\t\t'
  chk "grounded ||| tier: 1 ||| vendor doc states X"             $'CANDIDATE\t1\tvendor doc states X'
  chk "GROUNDED ||| tier:unknown ||| grounded but no tier"       $'CANDIDATE\t3\tgrounded but no tier'
  chk "UNGROUNDED ||| tier:1 ||| off-topic page"                 $'NOTGROUNDED\t\t'
  chk "NON-GROUNDED ||| tier:2 ||| not stated"                   $'NOTGROUNDED\t\t'
  if [[ $fail -eq 0 ]]; then echo "SELF-CHECK PASS"; else echo "SELF-CHECK FAIL"; exit 1; fi
  exit 0
fi

STACK="${1:?Usage: shadow-enrich-run.sh <stack> | --self-check}"

# Reset the output FIRST, before any failable check below. If the Brave key /
# resolve / dispatch is missing we exit with an EMPTY manifest, never leaving a
# previous (possibly different-stack) run's candidates for the skill's verifier to
# re-grade as if fresh.
OUT="$STACKS_ROOT/dev/experiments/model-tier/live-diffs/enrich"
rm -rf "$OUT"; mkdir -p "$OUT"
CANDS="$OUT/candidates.tsv"   # gap_id<TAB>slug<TAB>verdict<TAB>url<TAB>tier<TAB>claim<TAB>excerpt — the verifier dispatch manifest
: > "$CANDS"

[[ -f "$BRAVE_KEY_FILE" ]] || { echo "ERROR: no Brave key at $BRAVE_KEY_FILE" >&2; exit 1; }
BRAVE_KEY="$(cat "$BRAVE_KEY_FILE")"

LIB="$(bash "$STACKS_ROOT/scripts/resolve-library.sh")" || { echo "ERROR: could not resolve library" >&2; exit 1; }
cd "$LIB" || { echo "ERROR: cannot cd into library: $LIB" >&2; exit 1; }
DEV="$STACK/dev/enrich"
DISPATCH="$DEV/dispatch.tsv"
[[ -f "$DISPATCH" ]] || { echo "ERROR: no $DISPATCH — run enrich through prep+gate first (finish clears it)" >&2; exit 1; }

# Dedup set = the SAME filed-source URLs `enrich.sh prep` already built (it matches
# **Source:**/Source:/source_url: headers and excludes incoming/trash/.raw). Reuse
# its manifest rather than re-grep with a narrower pattern that would diverge from
# what production dedups against. Transient: present between gate and finish.
FILED="$OUT/filed-urls.txt"
FILED_SRC="$DEV/_filed-sources.tsv"   # slug<TAB>url, written by prep
[[ -f "$FILED_SRC" ]] && cut -f2 "$FILED_SRC" | sort -u > "$FILED" || : > "$FILED"

brave_search() { # <query> -> up to N_RESULTS urls; returns non-zero if the CALL errored
  # --fail makes curl exit non-zero on an HTTP error (rate limit, auth, 5xx). We
  # capture to a var and return its exit so the caller can tell an infra outage
  # (search never ran) from a genuine empty result set — otherwise both look like
  # "no source found" and downtime masquerades as a real grounding miss.
  local q="$1" raw
  raw=$(curl -sS --fail --max-time 20 -H "X-Subscription-Token: $BRAVE_KEY" -H "Accept: application/json" \
    --get "https://api.search.brave.com/res/v1/web/search" \
    --data-urlencode "q=$q" --data-urlencode "count=$N_RESULTS" 2>/dev/null) || return 1
  printf '%s' "$raw" | jq -r '.web.results[]?.url' 2>/dev/null | head -n "$N_RESULTS"
}

judge_prompt() { # <claim> <page-text-file> -> stdout
  cat <<EOF
You judge whether a fetched web page GROUNDS a specific knowledge claim. Grounding
means the page STATES the claim's exact assertion — the specific figure, mechanism,
or named result — not merely covers the same topic. Assign a source tier:
  1 official/vendor docs   2 peer-reviewed paper / vendor research
  3 practitioner blog / production case study   4 forum / general post
Be CONSERVATIVE: if the page is on-topic but silent on the claim's exact assertion,
that is NOT grounding — answer NOTGROUNDED.
OUTPUT exactly one line, nothing else:
<GROUNDED|NOTGROUNDED> ||| tier:<N> ||| <the exact sentence from the page that states the claim, or empty>

CLAIM: $1

PAGE TEXT:
$(cat "$2")

OUTPUT one line as specified.
EOF
}

n=0 candidates=0 weak=0 nosource=0 dup_skipped=0 fetch_failed=0 search_failed=0 infer_failed=0
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

while IFS=$'\t' read -r batch_tag gap_id slug claim reason; do
  [[ -n "${gap_id:-}" ]] || continue
  n=$((n+1))
  found=""
  # search once on the claim text (the harness owns query formation; one query per
  # gap keeps Brave quota bounded — the advisory grade does not need query tuning).
  # A failed search (outage/rate limit) is recorded as SEARCHFAIL, NOT NOSOURCE, so
  # infra downtime is never mistaken for a genuine grounding miss.
  if ! brave_search "$claim" > "$work/urls.txt"; then
    printf '%s\t%s\tSEARCHFAIL\t\t\t%s\t\n' "$gap_id" "$slug" "$claim" >> "$CANDS"
    search_failed=$((search_failed+1)); continue
  fi
  mapfile -t urls < "$work/urls.txt"
  for url in "${urls[@]}"; do
    [[ -n "$url" ]] || continue
    if [[ "$(bash "$DEDUP" "$url" "$FILED")" == "DUP" ]]; then dup_skipped=$((dup_skipped+1)); continue; fi
    if ! bash "$FETCH" "$url" --max-words "$FETCH_WORDS" > "$work/page.txt" 2>/dev/null; then fetch_failed=$((fetch_failed+1)); continue; fi
    [[ -s "$work/page.txt" ]] || { fetch_failed=$((fetch_failed+1)); continue; }
    judge_prompt "$claim" "$work/page.txt" > "$work/prompt.txt"
    if ! NUM_CTX="${NUM_CTX:-16384}" bash "$INFER" "$MODEL" "$work/prompt.txt" "$work/judge.txt" 2>/dev/null; then infer_failed=$((infer_failed+1)); continue; fi
    line=$(grep -m1 '|||' "$work/judge.txt" || true)
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r verdict tier excerpt < <(judge_to_verdict "$line") || true
    if [[ "$verdict" == "CANDIDATE" || "$verdict" == "WEAK" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$gap_id" "$slug" "$verdict" "$url" "$tier" "$claim" "$excerpt" >> "$CANDS"
      [[ "$verdict" == "CANDIDATE" ]] && candidates=$((candidates+1)) || weak=$((weak+1))
      found=1
      break   # first grounding source wins; stop fetching more for this gap
    fi
  done
  if [[ -z "$found" ]]; then
    printf '%s\t%s\tNOSOURCE\t\t\t%s\t\n' "$gap_id" "$slug" "$claim" >> "$CANDS"
    nosource=$((nosource+1))
  fi
done < "$DISPATCH"

echo "SHADOW_ENRICH_SUMMARY: stack=$STACK model=$MODEL gaps=$n candidate=$candidates weak=$weak nosource=$nosource dup_skipped=$dup_skipped fetch_failed=$fetch_failed search_failed=$search_failed infer_failed=$infer_failed -> $CANDS" >&2
