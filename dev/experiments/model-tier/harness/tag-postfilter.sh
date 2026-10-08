#!/usr/bin/env bash
# tag-postfilter.sh <article-file>
#
# Drops any frontmatter `tags:` entry not in TAG_VOCAB, the target stack's
# allowed_tags (space-separated, exported by the shadow runner). Rewrites
# the file's tags line(s) in place, so a local draft never ships a tag the
# model invented.
#
# Handles both frontmatter shapes: flow style `tags: [a, b, c]` and block
# style `tags:` followed by `  - a` lines.
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

# Only the frontmatter (between the first two `---` lines) is filtered; the body
# passes through untouched, so a body bullet or a `tags:` line in prose is never read.
tmp=$(mktemp)
mode=none fences=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == "---" ]]; then
    fences=$((fences+1)); mode=none
    echo "$line"
  elif [[ $fences -ne 1 ]]; then
    echo "$line"
  elif [[ "$line" =~ ^tags:[[:space:]]*\[(.*)\]$ ]]; then
    IFS=',' read -ra tags <<< "${BASH_REMATCH[1]}"
    kept=()
    for t in "${tags[@]}"; do
      t="$(echo "$t" | xargs)"
      [[ -z "$t" ]] && continue
      in_vocab "$t" && kept+=("$t")
    done
    joined=""
    for t in "${kept[@]}"; do
      joined="${joined:+$joined, }$t"
    done
    echo "tags: [$joined]"
    mode=none
  elif [[ "$line" == "tags:" ]]; then
    echo "$line"
    mode=list
  elif [[ "$mode" == "list" && "$line" =~ ^[[:space:]]*-[[:space:]]+(.+)$ ]]; then
    t="$(echo "${BASH_REMATCH[1]}" | xargs)"
    in_vocab "$t" && echo "  - $t"
  else
    mode=none
    echo "$line"
  fi
done < "$file" > "$tmp"
mv "$tmp" "$file"
