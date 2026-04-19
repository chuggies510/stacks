#!/usr/bin/env bash
set -euo pipefail

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

declare -A allowed_map=()
while IFS= read -r t; do
  [[ -z "$t" ]] && continue
  allowed_map["$t"]=1
done <<< "$allowed"

articles_dir="$stack_root/articles"
if [[ ! -d "$articles_dir" ]]; then
  exit 0
fi

drift_found=0
shopt -s nullglob
for article in "$articles_dir"/*.md; do
  slug=$(basename "$article" .md)

  # Parse frontmatter tags: accept block list or inline flow list (synthesizer may emit either).
  tags=$(awk '
    BEGIN { in_fm = 0; in_tags = 0; fm_count = 0 }
    /^---[[:space:]]*$/ {
      fm_count++
      if (fm_count == 1) { in_fm = 1; next }
      if (fm_count == 2) { exit }
    }
    in_fm && /^tags:[[:space:]]*\[/ {
      line = $0
      sub(/^tags:[[:space:]]*\[/, "", line)
      sub(/\].*$/, "", line)
      n = split(line, arr, ",")
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]"'\'']+|[[:space:]"'\'']+$/, "", arr[i])
        if (arr[i] != "") print arr[i]
      }
      in_tags = 0
      next
    }
    in_fm && /^tags:[[:space:]]*$/ { in_tags = 1; next }
    in_fm && in_tags && /^[[:space:]]*-[[:space:]]*/ {
      item = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", item)
      gsub(/^[[:space:]"'\'']+|[[:space:]"'\'']+$/, "", item)
      if (item != "") print item
      next
    }
    in_fm && in_tags && /^[^[:space:]-]/ { in_tags = 0 }
  ' "$article")

  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    if [[ -z "${allowed_map[$tag]:-}" ]]; then
      echo "TAG_DRIFT: $slug: $tag" >&2
      drift_found=1
    fi
  done <<< "$tags"
done

if (( drift_found )); then
  exit 1
fi
exit 0
