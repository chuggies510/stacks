#!/usr/bin/env bash
set -euo pipefail

# Rewrite a source file's citation path across a stack's articles after W3 files
# it from incoming/ to its publisher dir. W1/W2 cite a source as
# `sources/incoming/{fname}` (where it lived during synthesis); W3's mv then
# orphans every such ref. This rewrites `sources/incoming/{fname}` →
# `sources/{publisher}/{fname}` in one pass. Matching on the `sources/incoming/`
# substring preserves any leading prefix, so both forms are caught:
#   frontmatter  sources/incoming/X        → sources/{pub}/X
#   body         {stack}/sources/incoming/X → {stack}/sources/{pub}/X
# Also serves as the one-shot migration for libraries cataloged before this fix.
#
# Usage: rewrite-source-refs.sh <articles_dir> <fname> <publisher>

if [[ $# -ne 3 ]]; then
  echo "usage: rewrite-source-refs.sh <articles_dir> <fname> <publisher>" >&2
  exit 2
fi

ARTICLES_DIR=$1; FNAME=$2; PUB=$3

[[ -d "$ARTICLES_DIR" ]] || { echo "no articles dir: $ARTICLES_DIR" >&2; exit 0; }

# W0 rejects parens in source filenames, but escape regex/sed metachars anyway so
# a literal `.` in a fname can't match more than intended.
esc=$(printf '%s' "$FNAME" | sed 's/[.[\*^$/]/\\&/g')

shopt -s nullglob
arts=("$ARTICLES_DIR"/*.md)
(( ${#arts[@]} )) || exit 0
sed -i "s#sources/incoming/${esc}#sources/${PUB}/${esc}#g" "${arts[@]}"
