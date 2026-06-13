#!/usr/bin/env bash
set -euo pipefail

# Gate a batch of expected output paths: check each was freshly written (size +
# mtime) then (optionally) assert-structure; aggregate failures; exit 1 on any.
#
# Usage:
#   bash gate-batch.sh <dispatch_epoch> <agent_label> <structure_kind> <path>...
#
# Arguments:
#   dispatch_epoch   Unix timestamp (seconds) captured before dispatch — each
#                    file's mtime must be strictly greater than this value.
#   agent_label      Label surfaced in AGENT_WRITE_FAILURE messages (e.g.
#                    "concept-identifier", "validator-parent-gate").
#   structure_kind   Type passed to assert-structure.sh.  Pass "-" to skip the
#                    structure check and run the write check only.
#   <path>...        One or more absolute paths to gate.
#
# Exit codes:
#   0   All paths pass both gates.
#   1   One or more paths failed; failure messages written to stderr by the
#       assert-* helpers, and a summary line printed to stdout.

if [[ $# -lt 4 ]]; then
  echo "usage: gate-batch.sh <dispatch_epoch> <agent_label> <structure_kind> <path>..." >&2
  exit 1
fi

DISPATCH_EPOCH=$1
AGENT_LABEL=$2
STRUCTURE_KIND=$3
shift 3

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

FAILED=()
for path in "$@"; do
  # Write-or-fail gate (size + mtime): the file must be non-empty AND freshly
  # written (mtime strictly newer than the pre-dispatch epoch). Size alone misses a
  # stale leftover; mtime alone misses an empty write.
  if [[ ! -s "$path" ]] || (( $(stat -c %Y "$path" 2>/dev/null || echo 0) <= DISPATCH_EPOCH )); then
    FAILED+=("$path")
  elif [[ "$STRUCTURE_KIND" != "-" ]]; then
    if ! "$SCRIPT_DIR/assert-structure.sh" "$path" "$STRUCTURE_KIND" "$AGENT_LABEL" 2>/dev/null; then
      FAILED+=("$path")
    fi
  fi
done

if (( ${#FAILED[@]} > 0 )); then
  printf 'AGENT_WRITE_FAILURE: %s batches ungated:\n' "$AGENT_LABEL"
  printf '  %s\n' "${FAILED[@]}"
  exit 1
fi
