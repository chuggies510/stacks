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
  concept-batch)
    # A source the extractor judges pure-reference (STACK.md discard test, #93)
    # yields no concepts. Instead of an empty file (indistinguishable from a real
    # extractor failure) it writes a receipted-empty sentinel: a lone
    # `# no-concepts: <reason>` line, so the operator sees WHY the source produced
    # nothing. A real concept block still passes; a file that is empty OR carries
    # neither a concept block nor a NON-empty-reason sentinel still fails — a
    # missing/empty batch file is far more often a real failure than a genuine
    # pure-reference source, so the default stays conservative.
    grep -qE '^## Concept:' "$path" \
      || grep -qE '^# no-concepts:[[:space:]]*[^[:space:]]' "$path" \
      || fail "missing '## Concept:' header (or a '# no-concepts: <reason>' sentinel line)"
    ;;
  dedup-md)
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
  audit-findings)
    # Per-batch validator output (#87 T7). The success signal is no longer a
    # today-dated last_verified per article (that date-gate false-failed nothing
    # but couldn't prove per-article coverage); it is a VALIDATED receipt row per
    # assigned article in this file. Structure check here = at least one receipt
    # row exists (the validator wrote real output); check-coverage.sh --verdict
    # VALIDATED does the per-slug reconciliation against the dispatch manifest.
    grep -qE '^VALIDATED'$'\t' "$path" \
      || fail "no VALIDATED receipt rows — validator wrote no per-article receipts"
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
