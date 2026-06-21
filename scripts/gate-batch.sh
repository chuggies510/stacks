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
#                    "source-extractor", "validator-parent-gate").
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

# Portable mtime in epoch seconds: GNU coreutils `stat -c %Y` (Linux, and macOS
# with Homebrew coreutils on PATH) vs BSD `stat -f %m` (stock macOS). Try GNU
# first, fall back to BSD, else 0. Without this, the wrong syntax silently returns
# nothing and the `|| echo 0` makes every file look older than the epoch — so
# every batch fails its gate on a host with only the other `stat`.
mtime_epoch() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

FAILED=()
for path in "$@"; do
  # Write-or-fail gate (size + mtime): the file must be non-empty AND freshly
  # written (mtime not older than the pre-dispatch epoch). Callers rm stale files
  # before dispatch, so mtime == epoch means written THIS run within the same
  # wall-clock second as the epoch capture — accept it (`<`, not `<=`, else a
  # fast same-second agent write is wrongly failed). Size alone misses a stale
  # leftover; mtime alone misses an empty write.
  if [[ ! -s "$path" ]] || (( $(mtime_epoch "$path") < DISPATCH_EPOCH )); then
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
