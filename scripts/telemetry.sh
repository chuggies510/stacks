#!/bin/bash
# Append a skill invocation record to ~/.chuggiesmart/telemetry.jsonl
# Usage: SKILL_NAME="stacks:new" bash telemetry.sh
#
# Environment:
#   SKILL_NAME  — required, e.g. "stacks:new"
#
# Always exits 0. Safe to call as: ... || true

SKILL_NAME="${SKILL_NAME:-unknown}"
PROJECT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
SESSION=$(grep "^session:" "$PROJECT/.claude/memory-bank/active-context.md" 2>/dev/null | awk '{print $2}')
SESSION="${SESSION:-0}"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG="$HOME/.chuggiesmart/telemetry.jsonl"

mkdir -p "$(dirname "$LOG")"
printf '%s\n' "$(jq -cn \
  --arg ts "$TS" \
  --arg session "$SESSION" \
  --arg skill "$SKILL_NAME" \
  --arg project "$PROJECT" \
  '{ts: $ts, session: $session, tool: "Skill", skill: $skill, project: $project}')" >> "$LOG"
exit 0
