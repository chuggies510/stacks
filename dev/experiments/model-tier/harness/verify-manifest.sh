#!/usr/bin/env bash
# verify-manifest.sh <stack> <local|cloud> <run-dir>
#
# Prints the article-verifier manifest for one run folder, one row per slug in
# dispatch-w2.tsv: slug<TAB>block<TAB>draft<TAB>prior<TAB>grade<TAB>repair (absolute
# paths, NONE when absent). `local` rows grade the local draft and repair a scratch
# copy; `cloud` rows grade the shipped cloud article, grade only. A local slug with no
# draft gets no row: the summary already counts it as a missing draft.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_ROOT="$(cd "$HERE/../../../.." && pwd)"
STACK="${1:?Usage: verify-manifest.sh <stack> <local|cloud> <run-dir>}"
MODE="${2:?Usage: verify-manifest.sh <stack> <local|cloud> <run-dir>}"
LD="${3:?Usage: verify-manifest.sh <stack> <local|cloud> <run-dir>}"   # the run folder shadow-synth-run.sh printed
LIB="$(bash "$STACKS_ROOT/scripts/resolve-library.sh")"
EX="$LIB/$STACK/dev/extractions"

cut -f2 "$EX/dispatch-w2.tsv" | grep . | while IFS= read -r slug; do
  prior="$EX/_prior-$slug.md"; [[ -f "$prior" ]] || prior=NONE
  case "$MODE" in
    local) draft="$LD/bodies/${slug}__local.md"; [[ -s "$draft" ]] || continue
           grade="$LD/verify/$slug.json"; repair="$LD/verify/${slug}__repaired.md" ;;
    cloud) draft="$LIB/$STACK/articles/$slug.md"
           grade="$LD/verify/$slug.cloud.json"; repair=NONE ;;
    *) echo "ERROR: mode must be local or cloud" >&2; exit 2 ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$slug" "$EX/_dedup-$slug.md" "$draft" "$prior" "$grade" "$repair"
done
