#!/usr/bin/env bats

# The launcher reads plugin.json; marketplace.json must match or it shows a stale
# version. CLAUDE.md mandates bumping both JSON files + the CHANGELOG every change.
# That was policy-only (no enforcement) — Codex #19. This makes a mismatch fail CI.

ROOT="${BATS_TEST_DIRNAME}/.."

@test "plugin.json and marketplace.json versions match" {
  p=$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")
  m=$(jq -r '.plugins[0].version' "$ROOT/.claude-plugin/marketplace.json")
  [ -n "$p" ] && [ "$p" != "null" ]
  [ "$p" = "$m" ]
}

@test "top CHANGELOG entry matches plugin.json version" {
  p=$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")
  c=$(grep -m1 '^## ' "$ROOT/CHANGELOG.md" | awk '{print $2}')
  [ "$p" = "$c" ]
}
