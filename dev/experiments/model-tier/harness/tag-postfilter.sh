#!/usr/bin/env bash
# tag-postfilter.sh <article-file>
#
# Drops any frontmatter `tags:` entry not in TAG_VOCAB, the target stack's
# allowed_tags (space-separated, exported by the shadow runner). Rewrites
# the file's tags line(s) in place, so a local draft never ships a tag the
# model invented.
#
# Reads either frontmatter list style and writes block style.
set -euo pipefail

if [[ "${1:-}" == "--self-check" ]]; then
  t=$(mktemp)
  printf -- '---\ntitle: T\ntags:\n  - llm\n  - invented\n---\ntags:\n- body bullet\n' > "$t"
  TAG_VOCAB="llm" bash "$0" "$t"
  got=$(cat "$t"); rm -f "$t"
  want=$'---\ntitle: T\ntags:\n  - llm\n---\ntags:\n- body bullet'
  if [[ "$got" == "$want" ]]; then echo "PASS"; exit 0; else echo "FAIL: got [$got]"; exit 1; fi
fi

# No default: a fallback list silently drops every tag of any other stack.
VOCAB="${TAG_VOCAB:?TAG_VOCAB must hold the allowed_tags of the stack}"

file="${1:?Usage: tag-postfilter.sh <article-file>}"
[[ -f "$file" ]] || { echo "ERROR: no such file: $file" >&2; exit 1; }

in_vocab() {
  local tag="$1" v
  for v in $VOCAB; do [[ "$tag" == "$v" ]] && return 0; done
  return 1
}

# shellcheck source=../../../../scripts/article-field.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../../scripts/article-field.sh"

# Read and rewrite through the shared frontmatter reader and writer, so only the
# frontmatter is touched and a body bullet or a `tags:` line in prose is never read.
tags=$(article_tags "$file")
[[ -n "$tags" ]] || exit 0   # no tags to filter: leave the draft as written
printf '%s\n' "$tags" | while IFS= read -r t; do if in_vocab "$t"; then printf '%s\n' "$t"; fi; done \
  | article_set_list tags "$file"
