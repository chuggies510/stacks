#!/usr/bin/env bash
# citation-normalizer.sh <article-file>
#
# Rewrites [source: slug] -> [slug] in place. The stacks article contract wants
# bare inline [source-slug] citations; qwen3-30b-a3b synthesis emits the verbose
# [source: slug] form (liminal S61 grade — the one remaining mechanical defect
# after the tag filter). Deterministic, zero content risk: only the citation
# wrapper changes, never the slug or the surrounding prose.
#
# Frontmatter is untouched — `sources:` there uses bare paths, never the
# [source: X] form, so a whole-file substitution is safe.
set -euo pipefail

if [[ "${1:-}" == "--self-check" ]]; then
  t=$(mktemp)
  printf 'A claim. [source: llm-as-judge] Another. [source:  rag ] Third [rag].\n' > "$t"
  bash "$0" "$t"
  got=$(cat "$t"); rm -f "$t"
  want='A claim. [llm-as-judge] Another. [rag] Third [rag].'
  if [[ "$got" == "$want" ]]; then echo "PASS"; exit 0; else
    echo "FAIL: got [$got] want [$want]"; exit 1; fi
fi

file="${1:?Usage: citation-normalizer.sh <article-file>}"
[[ -f "$file" ]] || { echo "ERROR: no such file: $file" >&2; exit 1; }
# [source:<optional ws><slug><optional ws>] -> [<slug>]. Slug = non-space,
# non-bracket run, so a stray trailing space inside the brackets is dropped.
sed -i -E 's/\[source:[[:space:]]*([^][:space:]]+)[[:space:]]*\]/[\1]/g' "$file"
