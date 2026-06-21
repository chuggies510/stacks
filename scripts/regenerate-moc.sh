#!/usr/bin/env bash
set -euo pipefail
# W4 MoC generator: rebuild index.md from articles, preserving Reading Paths section
# Usage: regenerate-moc.sh <stack_root>
# Reads: <stack_root>/articles/*.md and <stack_root>/index.md
# Writes: <stack_root>/index.md

STACK="$1"

ARTICLES_DIR="$STACK/articles"
INDEX="$STACK/index.md"

# 1. Extract and preserve the ## Reading Paths section from the existing index.md
READING_PATHS_BLOCK=""
if [[ -f "$INDEX" ]]; then
  READING_PATHS_BLOCK=$(awk '
    /^## Reading Paths/ { in_section=1 }
    in_section { buf = buf $0 "\n" }
    /^## / && !/^## Reading Paths/ && in_section { in_section=0; sub(/\n[^\n]*\n$/, "", buf) }
    END { print buf }
  ' "$INDEX")
fi

# 2. Gather all articles and group by tags[0]
declare -A TAG_GROUPS
while IFS= read -r article; do
  # Group by the first tag. Accept BOTH frontmatter forms normalize-tags.sh does:
  # an inline flow list (`tags: [a, b]`) and a block list (`tags:` then `  - a`).
  # Inline-only parsing here previously dropped inline-tagged articles to
  # "uncategorized" even though the STACK.md template demonstrates the inline form.
  tag=$(awk '
    /^tags:[[:space:]]*\[/ { line=$0; sub(/^tags:[[:space:]]*\[/,"",line); sub(/[],].*/,"",line); gsub(/^[[:space:]]+|[[:space:]]+$/,"",line); print line; exit }
    /^tags:/ { found=1; next }
    found && /^  - / { print $2; exit }
    found && !/^  -/ { exit }
  ' "$article")
  title=$(awk '/^title:/{print substr($0, 8); exit}' "$article")
  # Strip [[ ]] from the display label — titles that contain wikilink markup
  # would otherwise produce nested brackets that break the outer link (#60).
  display="${title//\[\[/}"; display="${display//\]\]/}"
  # Routing line: what the article covers / questions it answers, in asker's
  # terms. It's what makes index.md a recognition map instead of a title list,
  # so /stacks:lookup lands on the right article by pattern (#59). Omitted (bare link)
  # for articles synthesized before the field existed.
  routing=$(awk '/^routing:/{print substr($0, 10); exit}' "$article")
  slug=$(basename "$article" .md)
  tag="${tag:-uncategorized}"
  if [[ -n "$routing" ]]; then
    TAG_GROUPS["$tag"]+="- [[${slug}|${display}]] — ${routing}"$'\n'
  else
    TAG_GROUPS["$tag"]+="- [[${slug}|${display}]]"$'\n'
  fi
done < <(find "$ARTICLES_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | sort || true)

# 3. Write new index.md
{
  echo "# $(basename "$STACK"): Map of Contents"
  echo ""
  echo "*Auto-generated from article frontmatter. Edit only the Reading Paths section below.*"
  echo ""
  echo "## Articles"
  echo ""
  for tag in $(printf '%s\n' "${!TAG_GROUPS[@]}" | sort); do
    echo "### ${tag}"
    echo ""
    printf '%s' "${TAG_GROUPS[$tag]}"
    echo ""
  done
  if [[ -n "$READING_PATHS_BLOCK" ]]; then
    echo ""
    printf '%s\n' "$READING_PATHS_BLOCK"
  fi
} > "$INDEX"
