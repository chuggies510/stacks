#!/usr/bin/env bash
set -euo pipefail

# Canonicalize a source publisher into a stable directory slug, reusing an
# existing sources/<dir> when the normalized form already names one. Without
# this, "up.codes", "up-codes", and "cpsc.gov" each spawn their own publisher
# dir and fragment the source tree (stacks#66).
#
# Usage: normalize-publisher.sh <raw_publisher> [<sources_dir>]
# Prints the canonical slug to stdout.

raw=${1:-}
sources_dir=${2:-}

[[ -n "$raw" ]] || { echo "unknown"; exit 0; }

# 1. lowercase; separators (. _ / whitespace) -> -; drop other non-alnum/-;
#    collapse repeats; trim leading/trailing -.
slug=$(printf '%s' "$raw" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's#[._/[:space:]]+#-#g; s#[^a-z0-9-]##g; s#-+#-#g; s#^-+##; s#-+$##')
[[ -n "$slug" ]] || slug="unknown"

# 2. tld-stripped variant for matching only: up-codes -> up, cpsc-gov -> cpsc.
stripped=$(printf '%s' "$slug" | sed -E 's#-(gov|com|org|net|edu|codes|io|co)$##')
[[ -n "$stripped" ]] || stripped="$slug"

# 3. reuse an existing publisher dir when the normalized OR tld-stripped form
#    already names one (exact match first, then stripped). Otherwise the full
#    normalized slug is the new dir name.
if [[ -n "$sources_dir" && -d "$sources_dir" ]]; then
  for cand in "$slug" "$stripped"; do
    [[ -d "$sources_dir/$cand" ]] && { echo "$cand"; exit 0; }
  done
fi

echo "$slug"
