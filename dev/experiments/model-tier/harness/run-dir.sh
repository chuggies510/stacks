#!/usr/bin/env bash
# run-dir.sh <stack>
#
# Prints this batch's run folder, the one definition of its name:
#   dev/experiments/model-tier/live-diffs/runs/<RUN_ID_W2>-<label>
# RUN_ID_W2 comes from the stack's dev/extractions/run.env; the label from
# STACKS_RUN_LABEL (default `default`) names a variant, so variants of one batch
# never share a file. The drafter, the manifest builder and the summary all call it.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACKS_ROOT="$(cd "$HERE/../../../.." && pwd)"
STACK="${1:?Usage: run-dir.sh <stack>}"
LIB="$(bash "$STACKS_ROOT/scripts/resolve-library.sh")"
rid=$(grep -m1 '^RUN_ID_W2=' "$LIB/$STACK/dev/extractions/run.env" 2>/dev/null | cut -d= -f2)
[[ -n "$rid" ]] || { echo "ERROR: no RUN_ID_W2 in $LIB/$STACK/dev/extractions/run.env: run catalog through dedup first" >&2; exit 1; }
label="${STACKS_RUN_LABEL:-default}"
[[ "$label" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "ERROR: STACKS_RUN_LABEL may hold only letters, digits, dot, dash, underscore" >&2; exit 2; }
printf '%s\n' "$STACKS_ROOT/dev/experiments/model-tier/live-diffs/runs/$rid-$label"
