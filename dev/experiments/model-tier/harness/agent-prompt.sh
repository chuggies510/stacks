#!/usr/bin/env bash
# Slice the MODEL-FACING region out of a stacks agent definition, so a benchmark
# scores the prompt that actually ships instead of a hand-copy of it (#136).
#
# Agent files mix two audiences. Most of the file is instruction the model needs
# (judgment rules, output contract, worked examples). A minority is harness
# plumbing that is WRONG in a raw prompt: dispatch file paths, "write it with the
# Write tool", the batch framing. The split is not contiguous — a single sentence
# of plumbing sits inside an otherwise model-facing section — so the agent files
# carry multiple begin/end pairs and this concatenates every marked region in
# file order.
#
#   usage: bash agent-prompt.sh <agent-file>
#
# Adding a rule to an agent def now reaches the benchmark automatically. Adding
# one OUTSIDE the fences is the remaining way to drift, which is what the
# --self-check coverage assertion below is for.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$HERE/../../../../agents"

# The three agents whose benchmarks slice from them. A stage whose agent loses its markers
# (or whose markers stop enclosing the judgment) silently falls back to measuring
# nothing, which is the #136 failure wearing a different hat — so assert it here rather
# than discovering it in a run's scores.
#
# Each entry is: agent|min_lines|anchor_regex. The anchor is a phrase from the judgment
# that stage is actually benchmarked ON, so the check fails if that judgment leaves the
# fenced region — a line count alone passes a slice whose Judgment Bias was deleted,
# which is this repo's own shape-vs-content instrument error pointed at its own gate.
# validator is deliberately absent: after the #136 review its two harnesses were left
# on their own claim-shaped prompts (see validator-shadow.sh), so fencing it would guard
# a slice nothing consumes.
FENCED_AGENTS=(
  "source-extractor|20|Default to reuse; mint a new slug only as the exception"
  "article-synthesizer|40|KEEP THE SUBJECT NARROW"
  "enrichment|15|not merely the topic"
)

# Plumbing that must never reach a raw prompt. Each is a distinct leak class, not one
# phrase: a single grep for "with the Write tool" passes every other kind of leak.
IO_LEAKS=(
  'with the Write tool'
  'Write to: '
  'Write the file with'
  'in place with .Edit'
  'output path given in your dispatch'
)

if [[ "${1:-}" == "--self-check" ]]; then
  fails=0 passes=0
  pass() { printf 'ok   %s\n' "$1"; passes=$((passes+1)); }
  fail() { printf 'FAIL %s\n' "$1"; fails=$((fails+1)); }

  for spec in "${FENCED_AGENTS[@]}"; do
    IFS='|' read -r a minl anchor <<<"$spec"
    f="$AGENTS_DIR/$a.md"
    if ! out=$(bash "$0" "$f" 2>&1); then
      fail "$a did not slice: $out"
      continue
    fi
    n=$(printf '%s\n' "$out" | grep -c '')
    if [[ "$n" -ge "$minl" ]]; then pass "$a slices $n lines (min $minl)"
    else fail "$a sliced only $n lines, under its $minl floor (markers present but hollow)"; fi

    # The content check the line count cannot do.
    if printf '%s\n' "$out" | grep -qF "$anchor"; then pass "$a slice carries its benchmarked judgment"
    else fail "$a slice LOST its benchmarked judgment (no match for: $anchor)"; fi

    leaked=""
    for lk in "${IO_LEAKS[@]}"; do
      printf '%s\n' "$out" | grep -qE "$lk" && leaked="${leaked:+$leaked, }$lk"
    done
    if [[ -z "$leaked" ]]; then pass "$a slice is I/O-free"; else fail "$a slice leaks harness plumbing: $leaked"; fi
  done

  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  printf 'no markers here\n' > "$tmp/bare.md"
  bash "$0" "$tmp/bare.md" >/dev/null 2>&1 && fail "unfenced file should not slice" || pass "unfenced file refused"

  printf '<!-- bench:begin -->\ncontent\n' > "$tmp/unbal.md"
  bash "$0" "$tmp/unbal.md" >/dev/null 2>&1 && fail "unbalanced markers should not slice" || pass "unbalanced markers refused"

  printf '<!-- bench:begin -->\n<!-- bench:end -->\nreal content outside\n' > "$tmp/hollow.md"
  bash "$0" "$tmp/hollow.md" >/dev/null 2>&1 && fail "empty region should not slice" || pass "empty region refused"

  echo
  echo "agent-prompt self-check: $passes passed, $fails failed"
  [[ "$fails" -eq 0 ]]
  exit
fi

AGENT="${1:?usage: agent-prompt.sh <agents/NAME.md>}"
[[ -f "$AGENT" ]] || { echo "agent-prompt: no such agent file: $AGENT" >&2; exit 1; }

grep -q '<!-- bench:begin -->' "$AGENT" || {
  echo "agent-prompt: $AGENT has no <!-- bench:begin --> markers — it has not been fenced for benchmark use (#136)" >&2
  exit 1
}

# Unbalanced markers would silently truncate the prompt at the last begin, which
# is the exact failure mode this script exists to end. Check before slicing.
nb=$(grep -c '<!-- bench:begin -->' "$AGENT")
ne=$(grep -c '<!-- bench:end -->' "$AGENT")
[[ "$nb" -eq "$ne" ]] || {
  echo "agent-prompt: $AGENT has $nb begin markers and $ne end markers — unbalanced" >&2
  exit 1
}

out=$(awk '/<!-- bench:begin -->/{f=1;next} /<!-- bench:end -->/{f=0;next} f' "$AGENT")

# A fenced file that slices to nothing means the markers are present but misplaced.
[[ -n "${out//[[:space:]]/}" ]] || {
  echo "agent-prompt: $AGENT sliced to an empty prompt — markers are present but enclose nothing" >&2
  exit 1
}

printf '%s\n' "$out"
