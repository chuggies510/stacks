#!/usr/bin/env bash
# verify-manifest.sh <stack> <local|cloud>
#
# Prints the article-verifier manifest for this batch's run folder (run-dir.sh), one row per slug in
# dispatch-w2.tsv: slug<TAB>block<TAB>draft<TAB>prior<TAB>grade<TAB>repair (absolute
# paths, NONE when absent). `local` rows grade the local draft and repair a scratch
# copy; `cloud` rows grade the shipped cloud article, grade only. A local slug with no
# draft gets no row: the summary already counts it as a missing draft.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_ROOT="$(cd "$HERE/../../../.." && pwd)"
STACK="${1:?Usage: verify-manifest.sh <stack> <local|cloud>}"
MODE="${2:?Usage: verify-manifest.sh <stack> <local|cloud>}"
[[ "$MODE" == local || "$MODE" == cloud ]] || { echo "ERROR: mode must be local or cloud" >&2; exit 2; }
LIB="$(bash "$STACKS_ROOT/scripts/resolve-library.sh")"
EX="$LIB/$STACK/dev/extractions"
RUN_DIR="$(bash "$HERE/run-dir.sh" "$STACK")"

cut -f2 "$EX/dispatch-w2.tsv" | grep . | while IFS= read -r slug; do
  prior="$EX/_prior-$slug.md"; [[ -f "$prior" ]] || prior=NONE
  case "$MODE" in
    local) draft="$RUN_DIR/bodies/${slug}__local.md"; [[ -s "$draft" ]] || continue
           grade="$RUN_DIR/verify/$slug.json"; repair="$RUN_DIR/verify/${slug}__repaired.md" ;;
    cloud) draft="$LIB/$STACK/articles/$slug.md"
           grade="$RUN_DIR/verify/$slug.cloud.json"; repair=NONE ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$slug" "$EX/_dedup-$slug.md" "$draft" "$prior" "$grade" "$repair"
done
