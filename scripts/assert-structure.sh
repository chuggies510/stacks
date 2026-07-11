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
    # The sentinel is only accepted as the file's SOLE non-blank line: a
    # `grep` that matched it anywhere let `<prose>\n# no-concepts: x` (real
    # extracted content the model then wrongly waved off) pass W1, so dedup
    # skipped it and the source was filed out of incoming/ = silent data loss.
    if grep -qE '^## Concept:' "$path"; then
      :
    elif awk 'NF{n++; last=$0} END{exit !(n==1 && last ~ /^# no-concepts:[[:space:]]*[^[:space:]]/)}' "$path"; then
      :
    else
      fail "missing '## Concept:' header (or a lone '# no-concepts: <reason>' sentinel line)"
    fi
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
    # Every non-blank line is a tab record led by a verdict. Split on a real tab
    # (-F'\t') rather than matching '\t' in an ERE (not portable across awks).
    # Field-count rule is verdict-specific: CANDIDATE/WEAK/DUP carry the
    # downstream-load-bearing url/tier/title/quote columns, so they must be a
    # full 8 fields (an un-stripped tab inside a field shifts columns and is
    # caught here, not at parse time). A NOSOURCE row's trailing four fields are
    # empty by definition (no source, no url, no quote) and stage nothing, and
    # agents routinely emit it without padding the empties — so it only needs
    # the 3 leading fields (verdict, gap_ids, slugs). Requiring 8 there made
    # NOSOURCE-heavy batches false-fail the gate while finish consolidated them
    # fine.
    grep -qE '^(CANDIDATE|WEAK|DUP|NOSOURCE)'$'\t' "$path" \
      || fail "no enrichment findings rows (CANDIDATE/WEAK/DUP/NOSOURCE)"
    if awk -F'\t' '
      $0!="" {
        if ($1!~/^(CANDIDATE|WEAK|DUP|NOSOURCE)$/) bad=1
        else if ($1=="NOSOURCE") { if (NF<3) bad=1 }
        else if (NF!=8) bad=1
      } END{exit bad?1:0}' "$path"; then :; else
      fail "malformed enrichment findings line (CANDIDATE/WEAK/DUP need 8 tab fields; NOSOURCE needs >=3; all led by a verdict)"
    fi
    ;;
  *)
    fail "unknown type: $type"
    ;;
esac
