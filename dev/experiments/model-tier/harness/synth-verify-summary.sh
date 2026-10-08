#!/usr/bin/env bash
# synth-verify-summary.sh <extractions-dir> <run-dir> [tokens.tsv]
# synth-verify-summary.sh --self-check
#
# Advisory window (#109): score ONE catalog batch's local drafts against every slug
# in its dispatch-w2.tsv, so a missing draft, refusal, failed call, missing grade or
# malformed grade counts as a failure instead of shrinking the denominator. Reads:
#   <extractions-dir>/dispatch-w2.tsv, run.env, _dedup-<slug>.md  (the batch)
#   <run-dir>/synthesis.jsonl              (local draft status, this RUN_ID_W2)
#   <run-dir>/bodies/<slug>__local.md      (the local draft)
#   <run-dir>/verify/<slug>.json           (article-verifier grade of the local draft)
#   <run-dir>/verify/<slug>__repaired.md   (its repaired copy, when it listed fixes)
#   <run-dir>/verify/<slug>.cloud.json     (same verifier on the cloud article)
#   tokens.tsv: slug<TAB>cloud_write_tokens<TAB>verify_repair_tokens (optional)
# Clearance is derived from the counts, never read from the agent's boolean. Reads
# only; the operator reads the PROMOTE line and calls the flip.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# One jq pass per grade prints:
#   valid draft_clears repaired_clears over miss lost struct cites needs_repair
# Valid = counts are nonnegative integers, present <= total, the claim population
# reconciles with the block's bullets, a repair keeps that population, and (local
# grades only, $repair) a listed fix has a repair trial while no fix means no repair.
GRADE='if length != 1 then [0,0,0,0,0,0,0,0,0] | @tsv else .[0] |
  def nn: type=="number" and . >= 0 and . == floor;
  def counts: (.recall_total|nn) and (.recall_present|nn) and (.over_claims|nn) and (.prior_lost|nn)
    and (.structural_pass|type=="boolean") and .recall_present <= .recall_total;
  def ok: .recall_present == .recall_total and .over_claims == 0 and .prior_lost == 0 and .structural_pass;
  ( counts and (.citation_fixes|nn) and (.excluded|type=="array") and (.would_fix|type=="array")
    and .citation_fixes <= (.would_fix|length)
    and (.recall_total + (.excluded|length) == $bullets)
    and (if .repaired then (.repaired|counts) and .repaired.recall_total == .recall_total else true end)
    and (if $repair then (if (.would_fix|length) > 0 then (.repaired|type=="object") else .repaired == null end) else true end)
  ) as $valid
  | if $valid then
      [1, (if ok then 1 else 0 end), (if (.repaired // .) | ok then 1 else 0 end), .over_claims,
       (.recall_total - .recall_present), .prior_lost, (if .structural_pass then 0 else 1 end), .citation_fixes,
       (if (.would_fix|length) > 0 then 1 else 0 end)]
    else [0,0,0,0,0,0,0,0,0] end | @tsv end'
# A file counts only when it is nonempty and written after this batch's RUN_ID_W2, so
# a grade, draft or repair left from an earlier batch can never be read as this one's.
fresh() { [[ -s "$1" ]] && [[ "$(perl -e 'print +(stat shift)[9]' "$1")" -ge "$run_id" ]]; }

# Slurped, so a second object or trailing garbage makes the whole grade invalid.
grade() { jq -rs --argjson bullets "$2" --argjson repair "$3" "$GRADE" "$1" 2>/dev/null || echo "0 0 0 0 0 0 0 0 0"; }

run() {
  local ex="$1" ld="$2" tok="${3:-}"
  local dispatch="$ex/dispatch-w2.tsv"
  [[ -f "$dispatch" ]] || { echo "ERROR: no $dispatch" >&2; return 1; }
  local run_id; run_id=$(grep -m1 '^RUN_ID_W2=' "$ex/run.env" 2>/dev/null | cut -d= -f2)
  [[ -n "$run_id" ]] || { echo "ERROR: no RUN_ID_W2 in $ex/run.env" >&2; return 1; }

  local n=0 ok=0 refused=0 failed=0 nodraft=0 nograde=0 invalid=0 draft_clear=0 fixed_clear=0
  local cloud_graded=0 cloud_clear=0 graded=""
  local over=0 miss=0 lost=0 struct=0 cites=0 slug status g b v dc fc o m l st c nr
  while IFS= read -r slug; do
    n=$((n+1))
    status=$(jq -r --arg s "$slug" --arg r "$run_id" 'select(.item==$s and .run_id==$r) | .status' \
      "$ld/synthesis.jsonl" 2>/dev/null | tail -1) || status=""
    b=$(bash "$HERE/claim-count.sh" "$ex/_dedup-$slug.md" 2>/dev/null || echo 0)
    g="$ld/verify/$slug.cloud.json"
    if fresh "$g"; then
      read -r v dc _ < <(grade "$g" "$b" false)
      if [[ "$v" == 1 ]]; then cloud_graded=$((cloud_graded+1)); cloud_clear=$((cloud_clear+dc)); fi
    fi
    [[ "$status" != ok ]] || fresh "$ld/bodies/${slug}__local.md" || status=""
    case "$status" in
      ok) ;;
      refused) refused=$((refused+1)); echo "  $slug: local drafter refused"; continue ;;
      local-inference-failed|malformed) failed=$((failed+1)); echo "  $slug: local call failed or returned no article"; continue ;;
      *) nodraft=$((nodraft+1)); echo "  $slug: no local draft for run $run_id"; continue ;;
    esac
    ok=$((ok+1))
    g="$ld/verify/$slug.json"
    if ! fresh "$g"; then nograde=$((nograde+1)); echo "  $slug: no grade from this batch"; continue; fi
    read -r v dc fc o m l st c nr < <(grade "$g" "$b" true)
    [[ "$nr" == 0 ]] || fresh "$ld/verify/${slug}__repaired.md" || v=0
    if [[ "$v" != 1 ]]; then
      invalid=$((invalid+1)); echo "  $slug: grade rejected (bad counts, population != $b bullets, or a fix with no repaired copy)"; continue
    fi
    graded="$graded $slug"
    draft_clear=$((draft_clear+dc)); fixed_clear=$((fixed_clear+fc))
    over=$((over+o)); miss=$((miss+m)); lost=$((lost+l)); struct=$((struct+st)); cites=$((cites+c))
  done < <(cut -f2 "$dispatch" | grep .)

  echo "slugs dispatched: $n (run $run_id)"
  echo "local drafts: ok $ok, refused $refused, failed $failed, missing $nodraft"
  echo "grades: missing $nograde, rejected $invalid"
  echo "draft clears floors: $draft_clear/$n"
  echo "after repair clears: $fixed_clear/$n"
  echo "cloud article clears (same block): $cloud_clear/$n, graded $cloud_graded"
  echo "draft defects: over-claims $over, recall misses $miss, prior lost $lost, structural fails $struct, citation fixes $cites"

  # Tokens count only when every graded slug has exactly one row of two whole numbers;
  # a second row for a graded slug is a conflicting measurement and blocks promotion.
  local tw=0 tv=0 rows=0 dup=0 tok_ok=0
  if [[ -n "$tok" && -s "$tok" ]]; then
    read -r rows dup tw tv < <(awk -F'\t' -v want="$graded" '
      BEGIN{ k=split(want, w, " "); for(i=1;i<=k;i++) need[w[i]]=1 }
      ($1 in need) && seen[$1]++ {d++; next}
      NF==3 && ($1 in need) && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {r++; a+=$2; b+=$3}
      END{print r+0, d+0, a+0, b+0}' "$tok")
    [[ "$rows" -eq "$ok" && "$dup" -eq 0 && "$ok" -gt 0 && "$tv" -lt "$tw" ]] && tok_ok=1
    echo "cloud tokens (total per agent, output share not reported): write-from-scratch $tw, verify+repair $tv, rows $rows of $ok"
  else
    echo "cloud tokens: not recorded"
  fi

  if [[ "$fixed_clear" -eq "$n" && "$cloud_graded" -eq "$n" && "$tok_ok" -eq 1 ]]; then
    echo "PROMOTE: criteria met; read a sample of drafts beside the cloud articles before flipping"
  else
    echo "PROMOTE: no (needs every slug clearing after repair, a cloud grade for every slug, and verify+repair tokens below write tokens)"
  fi
}

self_check() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  local ex="$d/ex" ld="$d/ld"; mkdir -p "$ex" "$ld/verify" "$ld/bodies"
  printf 'RUN_ID_W2=1000000000\n' > "$ex/run.env"
  local s all="a b c d e f g h i j"; : > "$ex/dispatch-w2.tsv"
  for s in $all; do
    printf '0\t%s\n' "$s" >> "$ex/dispatch-w2.tsv"
    printf 'slug: %s\n\n### Claims\n- one\n- two\n- three\n' "$s" > "$ex/_dedup-$s.md"
  done
  for s in a b c d h i j; do
    printf '{"item":"%s","run_id":"1000000000","status":"ok"}\n' "$s" >> "$ld/synthesis.jsonl"
    echo draft > "$ld/bodies/${s}__local.md"
  done
  printf '{"item":"e","run_id":"1000000000","status":"refused"}\n{"item":"f","run_id":"1000000000","status":"malformed"}\n' >> "$ld/synthesis.jsonl"
  # g: only a stale record from another run, so it has no draft in this run
  printf '{"item":"g","run_id":"99","status":"ok"}\n' >> "$ld/synthesis.jsonl"
  local clean='"recall_total":3,"recall_present":3,"excluded":[],"over_claims":0,"prior_lost":0,"structural_pass":true,"citation_fixes":0,"would_fix":[],"repaired":null'
  local fixed='"repaired":{"recall_total":2,"recall_present":2,"over_claims":0,"prior_lost":0,"structural_pass":true}'
  printf '{%s}\n' "$clean" > "$ld/verify/a.json"
  printf '{%s}\n' "$clean" > "$ld/verify/a.cloud.json"
  # b.cloud: a grade-only cloud grade may list a fix without a repair and still count
  printf '%s\n' '{"recall_total":3,"recall_present":3,"excluded":[],"over_claims":0,"prior_lost":0,"structural_pass":true,"citation_fixes":1,"would_fix":["cite"],"repaired":null}' > "$ld/verify/b.cloud.json"
  # b: over-claim in the draft, fixed by the repair trial, repaired copy on disk
  printf '{"recall_total":2,"recall_present":2,"excluded":["x lost a tier conflict"],"over_claims":1,"prior_lost":0,"structural_pass":true,"citation_fixes":1,"would_fix":["trim"],%s}\n' "$fixed" > "$ld/verify/b.json"
  echo repaired > "$ld/verify/b__repaired.md"
  # c: present > total
  printf '%s\n' '{"recall_total":3,"recall_present":4,"excluded":[],"over_claims":0,"prior_lost":0,"structural_pass":true,"citation_fixes":0,"would_fix":[],"repaired":null}' > "$ld/verify/c.json"
  # d: population does not reconcile with the 3 bullets (and the agent says it clears)
  printf '%s\n' '{"recall_total":2,"recall_present":2,"excluded":[],"over_claims":0,"prior_lost":0,"structural_pass":true,"clears_floors":true,"citation_fixes":0,"would_fix":[],"repaired":null}' > "$ld/verify/d.json"
  # h: lists a fix but ran no repair trial
  printf '%s\n' '{"recall_total":3,"recall_present":3,"excluded":[],"over_claims":0,"prior_lost":0,"structural_pass":true,"citation_fixes":1,"would_fix":["cite"],"repaired":null}' > "$ld/verify/h.json"
  # i: repair metadata but no repaired copy written
  printf '{"recall_total":2,"recall_present":2,"excluded":["y"],"over_claims":1,"prior_lost":0,"structural_pass":true,"citation_fixes":0,"would_fix":["trim"],%s}\n' "$fixed" > "$ld/verify/i.json"
  # j: the repair shrinks the claim population to hide a recall miss
  printf '%s\n' '{"recall_total":3,"recall_present":0,"excluded":[],"over_claims":0,"prior_lost":0,"structural_pass":true,"citation_fixes":0,"would_fix":["restore all"],"repaired":{"recall_total":0,"recall_present":0,"over_claims":0,"prior_lost":0,"structural_pass":true}}' > "$ld/verify/j.json"
  echo repaired > "$ld/verify/j__repaired.md"
  printf 'a\t9000\t3000\nb\t9000\t4000\n' > "$d/tokens.tsv"

  local out fail=0 want
  out=$(run "$ex" "$ld" "$d/tokens.tsv" 2>&1) || true
  for want in 'slugs dispatched: 10 (run 1000000000)' 'local drafts: ok 7, refused 1, failed 1, missing 1' \
      'grades: missing 0, rejected 5' 'draft clears floors: 1/10' 'after repair clears: 2/10' \
      'cloud article clears (same block): 2/10, graded 2' \
      'draft defects: over-claims 1, recall misses 0, prior lost 0, structural fails 0, citation fixes 1' \
      'cloud tokens (total per agent, output share not reported): write-from-scratch 18000, verify+repair 7000, rows 2 of 7'; do
    grep -qxF "$want" <<<"$out" || { echo "FAIL: missing line: $want"; fail=1; }
  done
  grep -q '^PROMOTE: no' <<<"$out" || { echo "FAIL: mixed batch promoted"; fail=1; }

  # every slug clean, cloud graded, one token row each: promotes
  : > "$ld/synthesis.jsonl"; : > "$d/tokens.tsv"
  for s in $all; do
    printf '{%s}\n' "$clean" > "$ld/verify/$s.json"; printf '{%s}\n' "$clean" > "$ld/verify/$s.cloud.json"
    printf '{"item":"%s","run_id":"1000000000","status":"ok"}\n' "$s" >> "$ld/synthesis.jsonl"
    echo draft > "$ld/bodies/${s}__local.md"; printf '%s\t9000\t3000\n' "$s" >> "$d/tokens.tsv"
  done
  out=$(run "$ex" "$ld" "$d/tokens.tsv" 2>&1) || true
  grep -q '^PROMOTE: criteria met' <<<"$out" || { echo "FAIL: clean batch did not promote"; fail=1; }
  # a missing token row blocks promotion
  grep -v '^j' "$d/tokens.tsv" > "$d/t2"
  out=$(run "$ex" "$ld" "$d/t2" 2>&1) || true
  grep -q '^PROMOTE: no' <<<"$out" || { echo "FAIL: promoted with a missing token row"; fail=1; }
  # a duplicate token row for a graded slug blocks promotion
  { cat "$d/tokens.tsv"; printf 'a\t9000\t15000\n'; } > "$d/t3"
  out=$(run "$ex" "$ld" "$d/t3" 2>&1) || true
  grep -q '^PROMOTE: no' <<<"$out" || { echo "FAIL: promoted with a duplicate token row"; fail=1; }
  # a local grade with no listed fix may not claim a repaired result
  printf '%s\n' '{"recall_total":3,"recall_present":0,"excluded":[],"over_claims":0,"prior_lost":0,"structural_pass":true,"citation_fixes":0,"would_fix":[],"repaired":{"recall_total":3,"recall_present":3,"over_claims":0,"prior_lost":0,"structural_pass":true}}' > "$ld/verify/i.json"
  out=$(run "$ex" "$ld" "$d/tokens.tsv" 2>&1) || true
  grep -qxF 'grades: missing 0, rejected 1' <<<"$out" || { echo "FAIL: repaired claim with no listed fix was accepted"; fail=1; }
  # a grade counting citation fixes it does not list is rejected
  printf '%s\n' '{"recall_total":3,"recall_present":3,"excluded":[],"over_claims":0,"prior_lost":0,"structural_pass":true,"citation_fixes":2,"would_fix":[],"repaired":null}' > "$ld/verify/i.json"
  out=$(run "$ex" "$ld" "$d/tokens.tsv" 2>&1) || true
  grep -qxF 'grades: missing 0, rejected 1' <<<"$out" || { echo "FAIL: unlisted citation fixes were accepted"; fail=1; }
  # a clean object followed by a second object is rejected, not read as its first line
  { printf '{%s}\n' "$clean"; printf '{"recall_total":3}\n'; } > "$ld/verify/i.json"
  out=$(run "$ex" "$ld" "$d/tokens.tsv" 2>&1) || true
  grep -qxF 'grades: missing 0, rejected 1' <<<"$out" || { echo "FAIL: a two-object grade was accepted"; fail=1; }
  printf '{%s}\n' "$clean" > "$ld/verify/i.json"
  # a grade older than the batch is ignored, not read as this batch's grade
  touch -t 200001010000 "$ld/verify/i.json"
  out=$(run "$ex" "$ld" "$d/tokens.tsv" 2>&1) || true
  grep -qxF 'grades: missing 1, rejected 0' <<<"$out" || { echo "FAIL: a stale grade was read"; fail=1; }
  printf '{%s}\n' "$clean" > "$ld/verify/i.json"
  # a missing cloud grade blocks promotion
  rm "$ld/verify/j.cloud.json"
  out=$(run "$ex" "$ld" "$d/tokens.tsv" 2>&1) || true
  grep -q '^PROMOTE: no' <<<"$out" || { echo "FAIL: promoted with a missing cloud grade"; fail=1; }
  # no draft log at all: every slug counts as missing, no crash
  rm "$ld/synthesis.jsonl"
  out=$(run "$ex" "$ld" "$d/tokens.tsv" 2>&1) || true
  grep -qxF 'local drafts: ok 0, refused 0, failed 0, missing 10' <<<"$out" || { echo "FAIL: absent log not counted as missing"; fail=1; }

  if [[ $fail -eq 0 ]]; then echo "SELF-CHECK PASS (18 checks)"; else echo "$out"; echo "SELF-CHECK FAIL"; return 1; fi
}

case "${1:-}" in
  --self-check) self_check ;;
  ""|-h|--help) echo "Usage: synth-verify-summary.sh <extractions-dir> <run-dir> [tokens.tsv] | --self-check" >&2; exit 2 ;;
  *) run "$@" ;;
esac
