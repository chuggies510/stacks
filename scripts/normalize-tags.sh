#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=article-field.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/article-field.sh"

stack_root=${1:-$PWD}

stack_md="$stack_root/STACK.md"
if [[ ! -f "$stack_md" ]]; then
  echo "normalize-tags: STACK.md not found at $stack_md" >&2
  exit 1
fi

# Parse allowed_tags from STACK.md. Block-list form only (matches the template).
allowed=$(awk '
  BEGIN { in_block = 0 }
  /^allowed_tags:[[:space:]]*$/ { in_block = 1; next }
  in_block && /^[[:space:]]*-[[:space:]]*/ {
    item = $0
    sub(/^[[:space:]]*-[[:space:]]*/, "", item)
    sub(/[[:space:]]*#.*$/, "", item)
    gsub(/^[[:space:]"'\'']+|[[:space:]"'\'']+$/, "", item)
    if (item != "") print item
    next
  }
  in_block && /^[^[:space:]-]/ { in_block = 0 }
' "$stack_md")

if [[ -z "$allowed" ]]; then
  echo "normalize-tags: allowed_tags not declared, skipping drift check" >&2
  exit 0
fi

articles_dir="$stack_root/articles"
if [[ ! -d "$articles_dir" ]]; then
  exit 0
fi

drift_found=0
shopt -s nullglob
for article in "$articles_dir"/*.md; do
  slug=$(basename "$article" .md)

  tags=$(article_tags "$article")

  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    if ! grep -qxF "$tag" <<< "$allowed"; then
      echo "TAG_DRIFT: $slug: $tag" >&2
      drift_found=1
    fi
  done <<< "$tags"
done

if (( drift_found )); then
  exit 1
fi
exit 0
