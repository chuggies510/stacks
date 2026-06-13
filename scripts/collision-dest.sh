#!/usr/bin/env bash
set -euo pipefail

# Compute a non-colliding destination path inside a directory for a filename.
#
# Usage:
#   bash collision-dest.sh <dir> <filename>
#
# Arguments:
#   dir        Target directory.
#   filename   Desired filename (basename only).
#
# Output:
#   Echoes the first non-colliding absolute path:
#     <dir>/<filename>              if that path does not exist, else
#     <dir>/<base>-1.<ext>          if that does not exist, else
#     <dir>/<base>-2.<ext>          ...
#
# The counter starts at 1 (not 2) and increments until a free slot is found.
# Behavior matches the collision-rename loop in skills/catalog-sources/SKILL.md.

if [[ $# -ne 2 ]]; then
  echo "usage: collision-dest.sh <dir> <filename>" >&2
  exit 1
fi

dir=$1
filename=$2

dest="$dir/$filename"
if [[ ! -f "$dest" ]]; then
  echo "$dest"
  exit 0
fi

base="${filename%.*}"
ext="${filename##*.}"
# When filename has no extension, ##*. returns the full filename (same as base).
# Guard: if ext equals the full filename, there is no extension.
if [[ "$ext" == "$filename" ]]; then
  ext=""
fi

counter=1
while true; do
  if [[ -n "$ext" ]]; then
    candidate="$dir/${base}-${counter}.${ext}"
  else
    candidate="$dir/${base}-${counter}"
  fi
  if [[ ! -f "$candidate" ]]; then
    echo "$candidate"
    exit 0
  fi
  ((counter++))
done
