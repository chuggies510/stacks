#!/usr/bin/env bash
set -uo pipefail

# Rank articles against a query by keyword match across the WHOLE file (body
# included), not just frontmatter title/tags. This is the retrieval step for
# /stacks:ask: title-only matching misses articles whose relevant content is in
# the body, which is the wall a library hits past a few dozen articles (#10).
#
# Usage:
#   rank-articles.sh <top_n> <query> <articles_dir> [<articles_dir> ...]
#
# Output (stdout): up to <top_n> lines, highest score first, each:
#   <score><TAB><path>
# A score of 0 is omitted. If nothing scores, output is empty — the caller
# treats that as "no match". The caller loads the listed files and synthesizes.
#
# Scoring (crude BM25-lite, deliberately simple): per query token, count
# case-insensitive occurrences in the file (body weight 1) plus a +5 bonus when
# the token appears in the `title:` frontmatter line. Tokens shorter than 3
# chars and a small stopword set are dropped.
#
# ponytail: O(tokens x files) greps, one grep per (token, file). Fine to a few
# hundred articles per query (~1s). Past low thousands, or when keyword match
# misses on pure semantic synonyms, escalate to a real index (qmd, #10) — that
# is the trigger, not article count alone.

if [[ $# -lt 3 ]]; then
  echo "usage: rank-articles.sh <top_n> <query> <articles_dir>..." >&2
  exit 2
fi

TOP_N=$1; QUERY=$2; shift 2

STOPWORDS=" the a an how do does what is are of to for in on with and or at by from as it that this you your i we my "

# Tokenize: lowercase, split on non-alphanumerics, drop short tokens + stopwords.
TOKENS=()
for raw in ${QUERY//[^a-zA-Z0-9]/ }; do
  t=${raw,,}
  [[ ${#t} -ge 3 ]] || continue
  [[ "$STOPWORDS" == *" $t "* ]] && continue
  TOKENS+=("$t")
done
# No usable tokens (query was all stopwords/short) → no ranking signal.
[[ ${#TOKENS[@]} -gt 0 ]] || exit 0

scored=""
for dir in "$@"; do
  [[ -d "$dir" ]] || continue
  while IFS= read -r -d '' f; do
    title_line=$(grep -m1 '^title:' "$f" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    score=0
    for t in "${TOKENS[@]}"; do
      cm=$(grep -Foi -- "$t" "$f" 2>/dev/null | wc -l)
      score=$((score + cm))
      [[ "$title_line" == *"$t"* ]] && score=$((score + 5))
    done
    (( score > 0 )) && scored+="${score}	${f}"$'\n'
  done < <(find "$dir" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null)
done

[[ -n "$scored" ]] || exit 0
printf '%s' "$scored" | sort -t$'\t' -k1,1 -rn | head -n "$TOP_N"
