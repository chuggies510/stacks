#!/usr/bin/env bats

# The launchers read three manifests; any mismatch presents a stale version.
# CLAUDE.md mandates bumping all three plus the CHANGELOG every change.

ROOT="${BATS_TEST_DIRNAME}/.."

@test "Claude, marketplace, and Codex manifest versions match" {
  p=$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")
  m=$(jq -r '.plugins[0].version' "$ROOT/.claude-plugin/marketplace.json")
  c=$(jq -r '.version' "$ROOT/.codex-plugin/plugin.json")
  [ -n "$p" ] && [ "$p" != "null" ]
  [ "$p" = "$m" ]
  [ "$p" = "$c" ]
}

@test "top CHANGELOG entry matches plugin.json version" {
  p=$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")
  c=$(grep -m1 '^## ' "$ROOT/CHANGELOG.md" | awk '{print $2}')
  [ "$p" = "$c" ]
}
