#!/usr/bin/env bash
set -euo pipefail

path=$1
dispatch_epoch=$2
agent_label=$3

if [[ ! -s "$path" ]]; then
  echo "AGENT_WRITE_FAILURE: empty or missing file: $path (agent=$agent_label)" >&2
  exit 1
fi

mtime=$(stat -c %Y "$path")
if (( mtime <= dispatch_epoch )); then
  echo "AGENT_WRITE_FAILURE: stale file: $path mtime=$mtime expected > $dispatch_epoch (agent=$agent_label)" >&2
  exit 1
fi
