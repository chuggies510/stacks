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
    # Every non-blank line is an 8-field tab record led by a verdict. Split on a
    # real tab (-F'\t') rather than matching '\t' in an ERE (not portable across
    # awks); then enforce the field count so an un-stripped tab inside a field
    # (which would shift columns downstream) is caught here, not at parse time.
    grep -qE '^(CANDIDATE|WEAK|DUP|NOSOURCE)'$'\t' "$path" \
      || fail "no enrichment findings rows (CANDIDATE/WEAK/DUP/NOSOURCE)"
    if awk -F'\t' '$0!="" { if (NF!=8 || $1!~/^(CANDIDATE|WEAK|DUP|NOSOURCE)$/) bad=1 } END{exit bad?1:0}' "$path"; then :; else
      fail "malformed enrichment findings line (need 8 tab fields led by a verdict)"
    fi
    ;;
  *)
    fail "unknown type: $type"
    ;;
esac
