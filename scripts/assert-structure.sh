#!/usr/bin/env bash
set -euo pipefail

path=${1:-}
type=${2:-}
agent_label=$3

if [[ -z "$path" || -z "$type" ]]; then
  echo "usage: assert-structure.sh <path> <type> <agent_label>" >&2
  exit 1
fi

fail() {
  echo "STRUCTURE_FAILURE: $1: $path (agent=$agent_label)" >&2
  exit 1
}

case "$type" in
  concept-batch|dedup-md)
    grep -qE '^## Concept:' "$path" || fail "missing '## Concept:' header"
    ;;
  dedup-meta)
    grep -qE '^ALL_SLUGS=' "$path"   || fail "missing ALL_SLUGS key"
    grep -qE '^ALL_SLUGS=[^[:space:]]' "$path" || fail "ALL_SLUGS has empty value"
    ;;
  article-md)
    grep -qE '^title:'           "$path" || fail "missing title field"
    grep -qE '^last_verified:'   "$path" || fail "missing last_verified field"
    ;;
  article-validated)
    # The read-and-fix validator no longer stamps inline marks (#57); the success
    # signal is a populated last_verified date (not the empty-string default).
    grep -qE '^last_verified:[[:space:]]*"?[0-9]{4}-[0-9]{2}-[0-9]{2}' "$path" \
      || fail "last_verified not set to a date (validator did not run)"
    ;;
  enrichment-findings)
    # Every non-blank line is a tab-led record whose first field is a verdict.
    grep -qE '^(CANDIDATE|WEAK|DUP|NOSOURCE)'$'\t' "$path" \
      || fail "no enrichment findings rows (CANDIDATE/WEAK/DUP/NOSOURCE)"
    if awk 'NF && $0 !~ /^(CANDIDATE|WEAK|DUP|NOSOURCE)\t/ {bad=1} END{exit bad?1:0}' "$path"; then :; else
      fail "malformed enrichment findings line (not KIND<TAB>...)"
    fi
    ;;
  *)
    fail "unknown type: $type"
    ;;
esac
