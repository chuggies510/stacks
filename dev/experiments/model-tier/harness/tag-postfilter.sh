#!/usr/bin/env bash
# tag-postfilter.sh <article-file>
#
# Drops any frontmatter `tags:` entry not in the stacks llm-stack vocab
# (hardcoded from synthesis-benchmark.md's "Tag vocabulary" fence). Rewrites
# the file's tags line(s) in place. Fixes the one qwen3-30b-a3b synthesis
# defect liminal flagged: an out-of-vocab tag invented per article (e.g.
# `safety`, `red-teaming`).
#
# Handles both frontmatter shapes: flow style `tags: [a, b, c]` and block
# style `tags:` followed by `  - a` lines.
set -euo pipefail

VOCAB="llm llmops evals llm-as-judge rag agents hallucination observability shadow-mode context-engineering prompt-engineering guardrails memory mcp multi-agent cost-economics fine-tuning"

file="${1:?Usage: tag-postfilter.sh <article-file>}"
[[ -f "$file" ]] || { echo "ERROR: no such file: $file" >&2; exit 1; }

in_vocab() {
  local tag="$1" v
  for v in $VOCAB; do [[ "$tag" == "$v" ]] && return 0; done
  return 1
}

tmp=$(mktemp)
mode=none
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^tags:[[:space:]]*\[(.*)\]$ ]]; then
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
  elif [[ "$mode" == "list" && "$line" =~ ^[[:space:]]*-[[:space:]]*(.+)$ ]]; then
    t="$(echo "${BASH_REMATCH[1]}" | xargs)"
    in_vocab "$t" && echo "  - $t"
  else
    mode=none
    echo "$line"
  fi
done < "$file" > "$tmp"
mv "$tmp" "$file"
