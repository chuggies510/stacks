#!/usr/bin/env bash
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
    END { if (in_section) print buf; else print buf }
  ' "$INDEX")
fi

# 2. Gather all articles and group by tags[0]
declare -A TAG_GROUPS
while IFS= read -r article; do
  tag=$(awk '/^tags:/{found=1; next} found && /^  - /{print $2; exit} found && !/^  -/{exit}' "$article")
  title=$(awk '/^title:/{print substr($0, 8); exit}' "$article")
  slug=$(basename "$article" .md)
  tag="${tag:-uncategorized}"
  TAG_GROUPS["$tag"]+="- [[${slug}|${title}]]\n"
done < <(find "$ARTICLES_DIR" -maxdepth 1 -name '*.md' | sort)

# 3. Write new index.md
{
  echo "# $(basename "$STACK"): Map of Contents"
  echo ""
  echo "*Auto-generated from article frontmatter. Edit only the Reading Paths section below.*"
  echo ""
  echo "## Articles"
  echo ""
  for tag in $(echo "${!TAG_GROUPS[@]}" | tr ' ' '\n' | sort); do
    echo "### ${tag}"
    echo ""
    printf "${TAG_GROUPS[$tag]}"
    echo ""
  done
  if [[ -n "$READING_PATHS_BLOCK" ]]; then
    echo ""
    printf '%s\n' "$READING_PATHS_BLOCK"
  fi
} > "$INDEX"
