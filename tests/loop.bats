#!/usr/bin/env bats

setup() {
  TEST_TMP=$(mktemp -d)
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/loop.sh"

  # Library structure
  mkdir -p "$TEST_TMP/lib/inbox"
  mkdir -p "$TEST_TMP/lib/mystack/sources/incoming"
  printf '# My Stack\n\n## Scope\n\nCovers svelte, reactivity, components, runes.\n' \
    > "$TEST_TMP/lib/mystack/STACK.md"

  # Fake config
  printf '{"library": "%s/lib"}' "$TEST_TMP" > "$TEST_TMP/config.json"

  # Mock claude binary — records calls, exits 0
  mkdir -p "$TEST_TMP/bin"
  printf '#!/usr/bin/env bash\necho "MOCK_CLAUDE: $*" >> "%s/claude-calls.log"\n' \
    "$TEST_TMP" > "$TEST_TMP/bin/claude"
  chmod +x "$TEST_TMP/bin/claude"

  export STACKS_CONFIG="$TEST_TMP/config.json"
  export PATH="$TEST_TMP/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "exits 0 when .loop-enabled missing (disabled)" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"disabled"* ]]
}

@test "exits 0 and logs no-op when inbox is empty" {
  touch "$TEST_TMP/lib/.loop-enabled"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"inbox empty"* ]]
  [ -f "$TEST_TMP/lib/loop.log" ]
  grep -q "inbox empty" "$TEST_TMP/lib/loop.log"
}

@test "log entries have ISO-8601 timestamp format" {
  touch "$TEST_TMP/lib/.loop-enabled"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -qE '\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\]' "$TEST_TMP/lib/loop.log"
}

@test "does not call claude when inbox is empty" {
  touch "$TEST_TMP/lib/.loop-enabled"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TMP/claude-calls.log" ]
}

@test "calls claude process-inbox when inbox has files" {
  touch "$TEST_TMP/lib/.loop-enabled"
  touch "$TEST_TMP/lib/inbox/file.md"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "process-inbox" "$TEST_TMP/claude-calls.log"
}

@test "calls claude catalog-sources for stacks with files in incoming/" {
  touch "$TEST_TMP/lib/.loop-enabled"
  touch "$TEST_TMP/lib/inbox/file.md"
  # Pre-populate incoming/ to simulate what process-inbox would have done
  touch "$TEST_TMP/lib/mystack/sources/incoming/filed.md"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "catalog-sources mystack" "$TEST_TMP/claude-calls.log"
}
