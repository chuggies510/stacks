#!/usr/bin/env bats

# The launchers read four manifests; any mismatch presents a stale version.
# CLAUDE.md mandates bumping all four plus the CHANGELOG every change.

ROOT="${BATS_TEST_DIRNAME}/.."

@test "Claude, marketplace, Codex, and agents-marketplace manifest versions match" {
  p=$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")
  m=$(jq -r '.plugins[0].version' "$ROOT/.claude-plugin/marketplace.json")
  c=$(jq -r '.version' "$ROOT/.codex-plugin/plugin.json")
  a=$(jq -r '.plugins[0].version' "$ROOT/.agents/plugins/marketplace.json")
  [ -n "$p" ] && [ "$p" != "null" ]
  [ "$p" = "$m" ]
  [ "$p" = "$c" ]
  [ "$p" = "$a" ]
}

@test "top CHANGELOG entry matches plugin.json version" {
  p=$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")
  c=$(grep -m1 -E '^## [0-9]+\.[0-9]+\.[0-9]+([[:space:]]|$)' "$ROOT/CHANGELOG.md" | awk '{print $2}')
  [ "$p" = "$c" ]
}
