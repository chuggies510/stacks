#!/usr/bin/env bash
# shadow-synth-run.sh <stack>
#
# Pilot (#109): after catalog `gate-w2`, run the LOCAL synth model on each W2
# concept block and log a local-vs-cloud diff to live-diffs/synthesis.jsonl for
# the liminal peer to grade. The cloud (sonnet) article is the authoritative one
# that ships; this is purely a shadow. Non-destructive: never touches articles/,
# sources, or any pipeline state file.
#
# Reads the TRANSIENT run files (_dedup-<slug>.md + dispatch-w2.tsv), which exist
# after gate-w2 and are cleared by `finish` — so this must run BETWEEN them.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_ROOT="$(cd "$HERE/../../../.." && pwd)"   # harness -> model-tier -> experiments -> dev -> repo root
STACK="${1:?Usage: shadow-synth-run.sh <stack>}"

LIB="$(bash "$STACKS_ROOT/scripts/resolve-library.sh")" || { echo "ERROR: could not resolve library" >&2; exit 1; }
cd "$LIB" || { echo "ERROR: cannot cd into library: $LIB" >&2; exit 1; }
DEV="$STACK/dev/extractions"
DISPATCH="$DEV/dispatch-w2.tsv"
[[ -f "$DISPATCH" ]] || { echo "ERROR: no $DISPATCH — run catalog through gate-w2 first (finish clears it)" >&2; exit 1; }

# allowed_tags from the stack's STACK.md (block-style list) -> TAG_VOCAB, so the
# tag filter judges against THIS stack's vocabulary, not the llm-stack default.
TAG_VOCAB="$(awk '
  /^allowed_tags:/ {f=1; next}
  f && /^[[:space:]]*-[[:space:]]/ {sub(/^[[:space:]]*-[[:space:]]*/,""); print; next}
  f && /^[^[:space:]#-]/ {exit}
' "$STACK/STACK.md" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
[[ -n "$TAG_VOCAB" ]] || echo "WARN: no allowed_tags parsed from $STACK/STACK.md — synth-shadow falls back to the llm-stack default vocab" >&2
export TAG_VOCAB
RUN_ID="$(grep -m1 '^RUN_ID_W2=' "$DEV/run.env" 2>/dev/null | cut -d= -f2)"; export RUN_ID="${RUN_ID:-manual}"

n=0 skipped=0 failed=0
while IFS=$'\t' read -r _wave slug; do
  [[ -n "${slug:-}" ]] || continue
  block="$LIB/$DEV/_dedup-$slug.md"
  article="$LIB/$STACK/articles/$slug.md"
  if [[ ! -f "$block" ]]; then echo "SKIP $slug: no concept block ($block)" >&2; skipped=$((skipped+1)); continue; fi
  cloud="$article"; [[ -f "$article" ]] || cloud="NONE"
  if bash "$HERE/synth-shadow.sh" "$block" "$cloud" "$slug"; then n=$((n+1)); else echo "SHADOW-FAIL $slug (logged as failed record)" >&2; failed=$((failed+1)); fi
done < "$DISPATCH"

echo "SHADOW_SUMMARY: stack=$STACK shadowed=$n skipped=$skipped failed=$failed run_id=$RUN_ID -> $STACKS_ROOT/dev/experiments/model-tier/live-diffs/synthesis.jsonl" >&2
