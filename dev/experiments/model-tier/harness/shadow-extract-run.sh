#!/usr/bin/env bash
# shadow-extract-run.sh <stack>
#
# Pilot (#109), extraction stage: after catalog `gate-w1`, run the LOCAL
# extraction model on each W1 source and apply the deterministic slug-prematch
# gate, writing per-source candidate rows + a NEAR/NEW survivor manifest for the
# cloud extraction-verifier to grade. The cloud source-extractor output that
# actually feeds W1b/dedup is authoritative and untouched — this only observes,
# to grade whether the local tier is safe to make authoritative for extraction.
#
# Mirrors shadow-synth-run.sh: reads the TRANSIENT run files (dispatch-w1.tsv),
# which exist after prep and are cleared by `finish` — run BETWEEN gate-w1 and
# finish. Non-destructive: never touches sources, extractions, articles, or any
# pipeline state file. Opt-in; the skill gates this on STACKS_LOCAL_SHADOW=1.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_ROOT="$(cd "$HERE/../../../.." && pwd)"   # harness -> model-tier -> experiments -> dev -> repo root
STACK="${1:?Usage: shadow-extract-run.sh <stack>}"
MODEL="${MODEL:-qwen3-30b-a3b-instruct}"
INFER="$HERE/local-infer.sh"
PREMATCH="$HERE/slug-prematch.sh"
OUT="$STACKS_ROOT/dev/experiments/model-tier/live-diffs/extractions"

LIB="$(bash "$STACKS_ROOT/scripts/resolve-library.sh")" || { echo "ERROR: could not resolve library" >&2; exit 1; }
cd "$LIB" || { echo "ERROR: cannot cd into library: $LIB" >&2; exit 1; }
DEV="$STACK/dev/extractions"
DISPATCH="$DEV/dispatch-w1.tsv"
[[ -f "$DISPATCH" ]] || { echo "ERROR: no $DISPATCH — run catalog through prep first (finish clears it)" >&2; exit 1; }

# Reset the output dir each run so the verifier + summary reflect only THIS batch,
# not a prior run's leftover survivor rows (the codex #109 reset-dir lesson).
rm -rf "$OUT"; mkdir -p "$OUT"
SURVIVORS="$OUT/survivors.tsv"   # slug<TAB>local_decision<TAB>prematch  — NEAR/NEW only, the verifier's input
: > "$SURVIVORS"

# EXISTING_SLUGS regenerated LIVE from the stack's articles (never a frozen
# snapshot — the corpus drifts as the stack grows). This is both the prematch set
# and what the model is told already exists.
EXIST_FILE="$OUT/existing-slugs.txt"
ls "$STACK"/articles/*.md 2>/dev/null | xargs -r -n1 basename | sed 's/\.md$//' | sort -u > "$EXIST_FILE"
EXIST_CSV="$(paste -sd, "$EXIST_FILE")"
[[ -n "$EXIST_CSV" ]] || echo "WARN: $STACK has no articles yet — every concept will be a genuine mint (first-catalog case)" >&2

# Tier rubric fed to the local model (the STACK.md hierarchy is the real trust
# order; this generic 1-4 rubric is enough for the advisory grade).
read -r -d '' RUBRIC <<'EOF' || true
Tier 1 Official — vendor docs, model cards, API reference, official cookbooks
Tier 2 Standard — peer-reviewed papers, vendor research blogs, established surveys
Tier 3 Practitioner — practitioner blogs, conference talks, production case studies
Tier 4 General — forum posts, X/HN/Reddit threads
EOF

extract_prompt() { # <source-file> -> stdout: the local extraction prompt
  cat <<EOF
You extract knowledge from ONE source into concept entries for a knowledge wiki.
For each DISTINCT, in-scope concept the source covers (in-scope = this stack's
domain knowledge; discard pure reference such as CLI-flag or API listings):
  - assign a kebab-case slug;
  - if an existing article in EXISTING_SLUGS covers this concept, REUSE that exact
    slug; only mint a NEW slug when none covers it;
  - assign tier 1-4 per the rubric.
Be CONSERVATIVE: do not fragment one concept into several, do not mint a slug for
a concept an existing article already covers, do not invent concepts.
OUTPUT: one line per concept, exactly:  <slug> | reuse:<existing-slug|NEW> | tier:<N>
Nothing else.

TIER RUBRIC:
$RUBRIC

EXISTING_SLUGS: $EXIST_CSV

SOURCE TEXT:
$(cat "$1")

OUTPUT: one line per concept, exactly <slug> | reuse:<existing-slug|NEW> | tier:<N>. Nothing else.
EOF
}

n=0 skipped=0 failed=0 total_candidates=0 total_survivors=0
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

while IFS=$'\t' read -r batch_tag src; do
  [[ -n "${src:-}" ]] || continue
  if [[ ! -f "$src" ]]; then echo "SKIP $batch_tag: no source ($src)" >&2; skipped=$((skipped+1)); continue; fi
  extract_prompt "$src" > "$work/prompt.txt"
  if ! NUM_CTX="${NUM_CTX:-16384}" bash "$INFER" "$MODEL" "$work/prompt.txt" "$work/out.txt" 2>"$work/err"; then
    echo "EXTRACT-FAIL $batch_tag ($(tail -1 "$work/err" 2>/dev/null))" >&2; failed=$((failed+1)); continue
  fi
  # parse "<slug> | reuse:... | tier:N" rows, prematch each emitted slug
  candfile="$OUT/${batch_tag}.tsv"; : > "$candfile"
  while IFS='|' read -r slug decision tier; do
    slug="$(echo "$slug" | tr -d '[:space:]')"; [[ -n "$slug" ]] || continue
    decision="$(echo "$decision" | tr -d '[:space:]')"
    pm="$(bash "$PREMATCH" "$slug" "$EXIST_FILE")"
    printf '%s\t%s\t%s\n' "$slug" "${decision:-NEW}" "$pm" >> "$candfile"
    total_candidates=$((total_candidates+1))
    # REUSE (exact/normalized collision) is harness-resolved and never sent to the
    # verifier; NEAR/NEW survive to the cloud grade.
    case "$pm" in REUSE:*) ;; *) printf '%s\t%s\t%s\n' "$slug" "${decision:-NEW}" "$pm" >> "$SURVIVORS"; total_survivors=$((total_survivors+1)) ;; esac
  done < <(grep -E '\|' "$work/out.txt")
  n=$((n+1))
done < "$DISPATCH"

echo "SHADOW_EXTRACT_SUMMARY: stack=$STACK sources=$n skipped=$skipped failed=$failed candidates=$total_candidates survivors(NEAR/NEW->verify)=$total_survivors -> $SURVIVORS" >&2
