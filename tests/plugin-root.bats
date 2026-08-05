#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."

resolver_for() {
  skill="$1"
  line=$(grep -n '^[[:space:]]*STACKS_ROOT=' "$skill" | head -1 | cut -d: -f1)
  sed -n "${line},$((line + 3))p" "$skill"
}

seed_plugin() {
  root="$1"
  mkdir -p "$root/scripts" "$root/skills/using-stacks"
  touch "$root/scripts/resolve-library.sh" "$root/skills/using-stacks/SKILL.md"
}

@test "all 39 skill fences resolve the newest shallow Codex cache under strict mode" {
  test_home="$BATS_TEST_TMPDIR/home with spaces"
  seed_plugin "$test_home/.codex/plugins/cache/stacks/stacks/0.78.3"
  seed_plugin "$test_home/.codex/plugins/cache/stacks/stacks/0.78.4"
  seed_plugin "$test_home/.codex/plugins/cache/stacks/stacks/0.78.4/.worktrees/stale"

  checks=0
  while IFS=: read -r skill line _; do
    resolver=$(sed -n "${line},$((line + 3))p" "$skill")

    run env -u STACKS_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_CACHE -u CODEX_HOME \
      HOME="$test_home" bash -c "set -euo pipefail
$resolver
printf '%s\\n' \"\$STACKS_ROOT\""
    [ "$status" -eq 0 ]
    [ "$output" = "$test_home/.codex/plugins/cache/stacks/stacks/0.78.4" ]
    checks=$((checks + 1))
  done < <(grep -nH '^[[:space:]]*STACKS_ROOT=' "$ROOT"/skills/*/SKILL.md)

  [ "$checks" -eq 39 ]
}

@test "resolver preserves explicit and Claude roots" {
  explicit="$BATS_TEST_TMPDIR/explicit"
  claude="$BATS_TEST_TMPDIR/claude"
  seed_plugin "$explicit"
  seed_plugin "$claude"
  resolver=$(resolver_for "$ROOT/skills/lookup/SKILL.md")

  run env STACKS_PLUGIN_ROOT="$explicit" CLAUDE_PLUGIN_ROOT="$claude" bash -c "$resolver
printf '%s\\n' \"\$STACKS_ROOT\""
  [ "$status" -eq 0 ]
  [ "$output" = "$explicit" ]

  run env -u STACKS_PLUGIN_ROOT CLAUDE_PLUGIN_ROOT="$claude" bash -c "$resolver
printf '%s\\n' \"\$STACKS_ROOT\""
  [ "$status" -eq 0 ]
  [ "$output" = "$claude" ]
}

@test "resolver follows Pi skill symlink to its physical plugin" {
  test_home="$BATS_TEST_TMPDIR/home"
  plugin="$BATS_TEST_TMPDIR/pi-package"
  seed_plugin "$plugin"
  mkdir -p "$test_home/.pi/agent/skills"
  ln -s "$plugin/skills/using-stacks" "$test_home/.pi/agent/skills/using-stacks"
  resolver=$(resolver_for "$ROOT/skills/lookup/SKILL.md")

  run env -u STACKS_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_CACHE -u CODEX_HOME \
    HOME="$test_home" PI_CODING_AGENT=true bash -c "set -euo pipefail
$resolver
printf '%s\\n' \"\$STACKS_ROOT\""
  [ "$status" -eq 0 ]
  [ "$output" = "$(readlink -f "$plugin")" ]
}

@test "resolver finds a Pi-managed git package" {
  test_home="$BATS_TEST_TMPDIR/home"
  plugin="$test_home/.pi/agent/git/github.com/chuggies510/stacks"
  seed_plugin "$plugin"
  resolver=$(resolver_for "$ROOT/skills/lookup/SKILL.md")

  run env -u STACKS_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_CACHE -u CODEX_HOME \
    HOME="$test_home" PI_CODING_AGENT=true bash -c "set -euo pipefail
$resolver
printf '%s\\n' \"\$STACKS_ROOT\""
  [ "$status" -eq 0 ]
  [ "$output" = "$plugin" ]
}

@test "resolver handles Codex cache success and failure under zsh strict mode" {
  test_home="$BATS_TEST_TMPDIR/zsh home with spaces"
  plugin="$test_home/.codex/plugins/cache/stacks/stacks/0.78.4"
  seed_plugin "$plugin"
  resolver=$(resolver_for "$ROOT/skills/lookup/SKILL.md")

  run env -u STACKS_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_CACHE -u CODEX_HOME \
    HOME="$test_home" zsh -c "set -euo pipefail
$resolver
printf '%s\\n' \"\$STACKS_ROOT\""
  [ "$status" -eq 0 ]
  [ "$output" = "$plugin" ]

  rm -rf "$test_home/.codex"
  run env -u STACKS_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_CACHE -u CODEX_HOME \
    HOME="$test_home" zsh -c "set -euo pipefail
$resolver"
  [ "$status" -eq 1 ]
  [ "$output" = "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." ]
}

@test "resolver rejects incomplete and missing roots before calling slash scripts" {
  test_home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$BATS_TEST_TMPDIR/incomplete/scripts"
  touch "$BATS_TEST_TMPDIR/incomplete/scripts/resolve-library.sh"
  resolver=$(resolver_for "$ROOT/skills/lookup/SKILL.md")

  run env STACKS_PLUGIN_ROOT="$BATS_TEST_TMPDIR/incomplete" HOME="$test_home" bash -c "$resolver"
  [ "$status" -eq 1 ]
  [ "$output" = "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." ]

  run env -u STACKS_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_CACHE -u CODEX_HOME \
    HOME="$test_home" bash -c "set -euo pipefail
$resolver"
  [ "$status" -eq 1 ]
  [ "$output" = "ERROR: Stacks plugin root not found. Set STACKS_PLUGIN_ROOT." ]
  [[ "$output" != *"/scripts/"* ]]
}
