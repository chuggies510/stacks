#!/usr/bin/env bash
set -euo pipefail

articles_dir=$1
glossary_path=$2

if [[ ! -f "$glossary_path" ]]; then
  echo "wikilink-pass: glossary not found, skipping pass" >&2
  exit 0
fi

compute_slug() {
  local text=$1
  echo "$text" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g' | sed 's/^-\+\|-\+$//g'
}

mapfile -t terms < <(grep -oP '(?<=\*\*)[^*]+(?=\*\*)' "$glossary_path" | sort -u)

for term in "${terms[@]}"; do
  term_slug=$(compute_slug "$term")

  for article in "$articles_dir"/*.md; do
    if [[ ! -f "$article" ]]; then
      continue
    fi

    article_slug=$(compute_slug "$(basename "$article" .md)")
    if [[ "$article_slug" == "$term_slug" ]]; then
      continue
    fi

    if grep -qi "\[\[$term\]\]" "$article"; then
      continue
    fi

    perl -i -pe 'BEGIN { $t = shift @ARGV; $done = 0 } unless ($done) { if (s/(?<!\[\[)(\b\Q$t\E\b)(?!\]\])/[[$1]]/i) { $done = 1 } }' "$term" "$article"
  done
done
