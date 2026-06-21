#!/usr/bin/env bash
# Append a skill invocation record to ~/.chuggiesmart/telemetry.jsonl
# Usage: SKILL_NAME="stacks:new" bash telemetry.sh
#
# Environment:
#   SKILL_NAME       — required, e.g. "stacks:new"
#   TELEMETRY_EXTRA  — optional JSON object merged into the record, e.g.
#                      '{"query":"vav sizing","articles":"VAV Systems"}'.
#                      Ignored unless it is valid JSON describing an object.
#
# Always exits 0. Safe to call as: ... || true

SKILL_NAME="${SKILL_NAME:-unknown}"
PROJECT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SESSION=$(grep "^session:" "$PROJECT/.claude/memory-bank/active-context.md" 2>/dev/null | awk '{print $2}')
SESSION="${SESSION:-0}"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG="$HOME/.chuggiesmart/telemetry.jsonl"

# Trust boundary: a caller's malformed/non-object extra must never break the lookup.
EXTRA="$TELEMETRY_EXTRA"
echo "$EXTRA" | jq -e 'type == "object"' >/dev/null 2>&1 || EXTRA='{}'

mkdir -p "$(dirname "$LOG")"
printf '%s\n' "$(jq -cn \
  --arg ts "$TS" \
  --arg session "$SESSION" \
  --arg skill "$SKILL_NAME" \
  --arg project "$PROJECT" \
  --argjson extra "$EXTRA" \
  '{ts: $ts, session: $session, tool: "Skill", skill: $skill, project: $project} + $extra')" >> "$LOG"
exit 0
