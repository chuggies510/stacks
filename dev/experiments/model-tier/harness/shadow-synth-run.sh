#!/usr/bin/env bash
# shadow-synth-run.sh <stack>
#
# Pilot (#109): after catalog `gate-w2`, run the LOCAL synth model (breathless
# vLLM, see local-infer.sh) on each W2 concept block and log a local-vs-cloud
# diff to live-diffs/synthesis.jsonl. The cloud article is the authoritative one
# that ships; this is purely a shadow. Non-destructive: never touches articles/,
# sources, or any pipeline state file.
#
# Reads this run's files (_dedup-<slug>.md, _prior-<slug>.md, dispatch-w2.tsv),
# which the stack's next catalog `prep` clears.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_ROOT="$(cd "$HERE/../../../.." && pwd)"   # harness -> model-tier -> experiments -> dev -> repo root
STACK="${1:?Usage: shadow-synth-run.sh <stack>}"

LIB="$(bash "$STACKS_ROOT/scripts/resolve-library.sh")" || { echo "ERROR: could not resolve library" >&2; exit 1; }
cd "$LIB" || { echo "ERROR: cannot cd into library: $LIB" >&2; exit 1; }
DEV="$STACK/dev/extractions"
DISPATCH="$DEV/dispatch-w2.tsv"
[[ -f "$DISPATCH" ]] || { echo "ERROR: no $DISPATCH: run catalog through gate-w2 first" >&2; exit 1; }

# allowed_tags from the stack's STACK.md (block-style list) -> TAG_VOCAB, so the
# tag filter judges against THIS stack's vocabulary.
TAG_VOCAB="$(awk '
  /^allowed_tags:/ {f=1; next}
  f && /^[[:space:]]*-[[:space:]]/ {sub(/^[[:space:]]*-[[:space:]]*/,""); print; next}
  f && /^[^[:space:]#-]/ {exit}
' "$STACK/STACK.md" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
[[ -n "$TAG_VOCAB" ]] || { echo "ERROR: no allowed_tags parsed from $STACK/STACK.md" >&2; exit 1; }
RUN_ID="$(grep -m1 '^RUN_ID_W2=' "$DEV/run.env" 2>/dev/null | cut -d= -f2)"; RUN_ID="${RUN_ID:-manual}"
# One folder per run: <batch RUN_ID_W2>-<label>. STACKS_RUN_LABEL names a variant
# (drafter, thinking setting), so variants of one batch can run side by side.
LABEL="${STACKS_RUN_LABEL:-default}"
[[ "$LABEL" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "ERROR: STACKS_RUN_LABEL may hold only letters, digits, dot, dash, underscore" >&2; exit 2; }
RUN_DIR="$STACKS_ROOT/dev/experiments/model-tier/live-diffs/runs/$RUN_ID-$LABEL"
mkdir -p "$RUN_DIR/bodies" "$RUN_DIR/verify"
export TAG_VOCAB RUN_ID RUN_DIR STACK_DIR="$LIB/$STACK" EX="$LIB/$DEV" HERE

# One slug per call, 4 at a time: the breathless server has 8 slots, and 4 leaves
# room for its other consumers. Each call prints one status word for the tally.
one() {
  local slug="$1" block="$EX/_dedup-$1.md" cloud="$STACK_DIR/articles/$1.md"
  if [[ ! -f "$block" ]]; then echo "SKIP $slug: no concept block ($block)" >&2; echo SKIP; return; fi
  [[ -f "$cloud" ]] || cloud="NONE"
  if bash "$HERE/synth-shadow.sh" "$block" "$cloud" "$slug"; then echo OK; else echo "SHADOW-FAIL $slug (logged as failed record)" >&2; echo FAIL; fi
}
export -f one
results=$(cut -f2 "$DISPATCH" | grep . | xargs -P 4 -I{} bash -c 'one "$1"' _ {})
n=$(grep -c '^OK$' <<<"$results" || true)
skipped=$(grep -c '^SKIP$' <<<"$results" || true)
failed=$(grep -c '^FAIL$' <<<"$results" || true)

echo "SHADOW_SUMMARY: stack=$STACK shadowed=$n skipped=$skipped failed=$failed run_id=$RUN_ID -> $RUN_DIR" >&2
echo "RUN_DIR=$RUN_DIR"
