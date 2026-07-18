#!/usr/bin/env bash
# ab-synth-delta.sh <concepts-snapshot-dir> <sonnet-grade-dir> <haiku-grade-dir> <out-jsonl> [run_id] [stack]
#
# Production self-test A/B (#95/#109). The synthesis stage ships the sonnet article
# and runs a haiku challenger in the shadow; BOTH are graded by stacks:article-verifier
# into two grade dirs. This joins them by slug and appends one paired-delta line per
# slug to the accumulating ab-synthesis.jsonl — the real-corpus evidence for the tier
# decision.
#
# The slug set is the CONCEPTS SNAPSHOT DIR (the W2 manifest, snapshotted before finish),
# NOT the sonnet-grade-present files — so a slug whose sonnet grade is missing is recorded
# as a failure, never silently dropped. Each arm is validated INDEPENDENTLY and per-slug:
# a missing grade -> arm null / status "missing"; an unparseable or field-incomplete grade
# -> arm null / status "invalid" (a grade lacking numeric recall fields must NOT falsely
# clear the floors). One bad grade never aborts the batch. Floor clearance is DERIVED from
# component fields, never the self-reported clears_floors. APPENDS to the out file.
#
#   bash ab-synth-delta.sh ab/RUN/concepts grade-sonnet grade-haiku ab-synthesis.jsonl RUN writing
#   bash ab-synth-delta.sh --self-check
set -euo pipefail

JQ_CLEARS='def clears($g): (($g.recall_present // -1) == ($g.recall_total // -2)) and (($g.over_claims // 1) == 0) and ($g.structural_pass == true);'

# load_arm <grade-file> -> prints a compact arm object (with derived clears_floors),
# or the literal MISSING / INVALID. A valid arm REQUIRES numeric recall_present,
# recall_total, over_claims and a boolean structural_pass — anything else is INVALID,
# so an incomplete grade cannot default its way to clears_floors:true.
load_arm() {
  local f="$1" arm
  [[ -f "$f" ]] || { echo "MISSING"; return; }
  if arm=$(jq -ce "$JQ_CLEARS"'
        select((.recall_present|type)=="number" and (.recall_total|type)=="number"
               and (.over_claims|type)=="number" and (.structural_pass|type)=="boolean")
        | {recall_present, recall_total, over_claims, structural_pass, clears_floors: clears(.)}
      ' "$f" 2>/dev/null) && [[ -n "$arm" ]]; then
    echo "$arm"
  else
    echo "INVALID"
  fi
}
mk_arg()    { case "$1" in MISSING|INVALID) echo "null";;  *) echo "$1";; esac; }
mk_status() { case "$1" in MISSING) echo missing;; INVALID) echo invalid;; *) echo ok;; esac; }

run() {
  local cdir="${1:?need concepts-snapshot dir}" sdir="${2:?need sonnet grade dir}" hdir="${3:?need haiku grade dir}"
  local out="${4:?need out jsonl}" run_id="${5:-}" stack="${6:-}"
  shopt -s nullglob
  local cfiles=("$cdir"/*.md)
  shopt -u nullglob
  [[ ${#cfiles[@]} -gt 0 ]] || { echo "No concept snapshots in $cdir — nothing to compare."; return 1; }

  local tmp; tmp=$(mktemp); trap 'rm -f "$tmp"' RETURN
  local cf slug s_arm h_arm line
  for cf in "${cfiles[@]}"; do
    slug=$(basename "$cf" .md)
    s_arm=$(load_arm "$sdir/$slug.json")
    h_arm=$(load_arm "$hdir/$slug.json")
    line=$(jq -n -c \
      --argjson S "$(mk_arg "$s_arm")" --argjson H "$(mk_arg "$h_arm")" \
      --arg run "$run_id" --arg stack "$stack" --arg slug "$slug" \
      --arg sst "$(mk_status "$s_arm")" --arg hst "$(mk_status "$h_arm")" '
      {
        item: $slug, run_id: $run, stack: $stack,
        sonnet: $S, haiku: $H,
        status: {sonnet: $sst, haiku: $hst},
        delta: (if ($S != null and $H != null)
                then {
                  over_claims:       ($H.over_claims - $S.over_claims),
                  recall_miss_delta: (($H.recall_total - $H.recall_present) - ($S.recall_total - $S.recall_present)),
                  both_clear:        ($S.clears_floors and $H.clears_floors),
                  haiku_regressed:   ($S.clears_floors and ($H.clears_floors | not))
                }
                else {incomparable: true} end)
      }') || { echo "WARN: could not build line for $slug — skipping"; continue; }
    printf '%s\n' "$line" >> "$tmp"
  done

  [[ -s "$tmp" ]] || { echo "No lines produced."; return 1; }
  cat "$tmp" >> "$out"   # ACCUMULATE — never truncate the running log

  jq -s -r '
    {
      n:       length,
      s_ok:    (map(select(.status.sonnet == "ok")) | length),
      h_ok:    (map(select(.status.haiku  == "ok")) | length),
      s_bad:   (map(select(.status.sonnet != "ok")) | length),
      h_bad:   (map(select(.status.haiku  != "ok")) | length),
      sclear:  (map(select(.sonnet.clears_floors == true)) | length),
      hclear:  (map(select(.haiku.clears_floors  == true)) | length),
      regress: (map(select(.delta.haiku_regressed == true)) | length),
      incomp:  (map(select(.delta.incomparable == true)) | length)
    }
    | "\(.n) slugs · haiku clears floors \(.hclear)/\(.h_ok) ok · sonnet \(.sclear)/\(.s_ok) ok · haiku regressions \(.regress) · incomparable \(.incomp) (sonnet-bad \(.s_bad), haiku-bad \(.h_bad))"
  ' "$tmp"
  echo "--- appended to $out (accumulating). haiku_regressed = sonnet cleared floors AND haiku did not; the tier flip needs this near zero across runs. Grader failures show as status!=ok / incomparable, not silent drops."
}

self_check() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  mkdir -p "$d/c" "$d/s" "$d/h"
  # Slug set is the concepts dir (the manifest). 6 slugs a..f exercise every path.
  local x; for x in a b c d e f; do printf 'concept %s\n' "$x" > "$d/c/$x.md"; done
  # a: both ok, both clear.
  printf '%s\n' '{"slug":"a","recall_total":6,"recall_present":6,"over_claims":0,"structural_pass":true,"clears_floors":true}' > "$d/s/a.json"
  printf '%s\n' '{"slug":"a","recall_total":6,"recall_present":6,"over_claims":0,"structural_pass":true,"clears_floors":true}' > "$d/h/a.json"
  # b: haiku over-claim breach but self-reports clears_floors:true (derive-don't-trust).
  printf '%s\n' '{"slug":"b","recall_total":5,"recall_present":5,"over_claims":0,"structural_pass":true,"clears_floors":true}' > "$d/s/b.json"
  printf '%s\n' '{"slug":"b","recall_total":5,"recall_present":5,"over_claims":2,"structural_pass":true,"clears_floors":true}' > "$d/h/b.json"
  # c: haiku recall breach.
  printf '%s\n' '{"slug":"c","recall_total":4,"recall_present":4,"over_claims":0,"structural_pass":true,"clears_floors":true}' > "$d/s/c.json"
  printf '%s\n' '{"slug":"c","recall_total":4,"recall_present":3,"over_claims":0,"structural_pass":true,"clears_floors":true}' > "$d/h/c.json"
  # d: haiku grade MISSING -> incomparable, haiku null/missing.
  printf '%s\n' '{"slug":"d","recall_total":3,"recall_present":3,"over_claims":0,"structural_pass":true,"clears_floors":true}' > "$d/s/d.json"
  # e: sonnet grade INVALID JSON -> must NOT abort the batch; sonnet null/invalid.
  printf '%s\n' '{"slug":"e", NOT JSON' > "$d/s/e.json"
  printf '%s\n' '{"slug":"e","recall_total":2,"recall_present":2,"over_claims":0,"structural_pass":true,"clears_floors":true}' > "$d/h/e.json"
  # f: haiku grade valid JSON but MISSING recall fields -> INVALID, must NOT falsely clear.
  printf '%s\n' '{"slug":"f","recall_total":2,"recall_present":2,"over_claims":0,"structural_pass":true,"clears_floors":true}' > "$d/s/f.json"
  printf '%s\n' '{"slug":"f","structural_pass":true,"clears_floors":true}' > "$d/h/f.json"

  local out="$d/ab.jsonl" summary; summary=$(run "$d/c" "$d/s" "$d/h" "$out" RUNX writing 2>&1)
  local fail=0
  grep -q '6 slugs' <<<"$summary"                 || { echo "FAIL: slug count (must be the 6-concept manifest, not grade-present)"; fail=1; }
  grep -q 'haiku clears floors 2/4 ok' <<<"$summary" || { echo "FAIL: haiku clears (a + e clear; b over-claim + c recall breached; d missing, f invalid — e's haiku is valid though its sonnet arm isn't)"; fail=1; }
  grep -q 'sonnet 5/5 ok' <<<"$summary"           || { echo "FAIL: sonnet clears (e invalid -> 5 ok, all clear)"; fail=1; }
  grep -q 'haiku regressions 2' <<<"$summary"     || { echo "FAIL: regressions (b,c)"; fail=1; }
  grep -q 'incomparable 3' <<<"$summary"          || { echo "FAIL: incomparable (d missing, e sonnet-invalid, f haiku-invalid)"; fail=1; }
  [[ $(jq -r 'select(.item=="b").haiku.clears_floors' "$out") == false ]] || { echo "FAIL: b haiku must DERIVE non-clear"; fail=1; }
  [[ $(jq -r 'select(.item=="d").status.haiku' "$out") == missing ]] || { echo "FAIL: d haiku status missing"; fail=1; }
  [[ $(jq -r 'select(.item=="e").status.sonnet' "$out") == invalid ]] || { echo "FAIL: e sonnet status invalid (batch did not abort)"; fail=1; }
  [[ $(jq -r 'select(.item=="f").haiku' "$out") == null ]] || { echo "FAIL: f haiku null (incomplete grade not accepted)"; fail=1; }
  [[ $(jq -r 'select(.item=="f").status.haiku' "$out") == invalid ]] || { echo "FAIL: f haiku status invalid (no false clear)"; fail=1; }
  [[ $(wc -l < "$out") -eq 6 ]] || { echo "FAIL: expected 6 appended lines"; fail=1; }
  if [[ $fail -eq 0 ]]; then echo "SELF-CHECK PASS"; else echo "SELF-CHECK FAIL"; return 1; fi
}

case "${1:-}" in
  --self-check) self_check ;;
  "" ) echo "Usage: ab-synth-delta.sh <concepts-snapshot-dir> <sonnet-grade-dir> <haiku-grade-dir> <out-jsonl> [run_id] [stack] | --self-check" >&2; exit 2 ;;
  * ) run "$@" ;;
esac
