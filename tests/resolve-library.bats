#!/usr/bin/env bats

setup() {
  TEST_TMP=$(mktemp -d)
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/resolve-library.sh"

  mkdir -p "$TEST_TMP/lib"
  printf '# Library Catalog\n' > "$TEST_TMP/lib/catalog.md"
  printf '{"library": "%s/lib"}' "$TEST_TMP" > "$TEST_TMP/config.json"
}

teardown() {
  rm -rf "$TEST_TMP"
}

@test "resolves library from STACKS_CONFIG" {
  STACKS_CONFIG="$TEST_TMP/config.json" run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TMP/lib" ]
}

@test "falls back to cwd when config missing but cwd is a library" {
  STACKS_CONFIG="$TEST_TMP/does-not-exist.json" run bash -c "cd '$TEST_TMP/lib' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TMP/lib" ]
}

@test "falls back to cwd when config points at a gone library" {
  printf '{"library": "%s/deleted"}' "$TEST_TMP" > "$TEST_TMP/config.json"
  STACKS_CONFIG="$TEST_TMP/config.json" run bash -c "cd '$TEST_TMP/lib' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TMP/lib" ]
}

@test "errors when no config and cwd is not a library" {
  STACKS_CONFIG="$TEST_TMP/does-not-exist.json" run bash -c "cd '$TEST_TMP' && bash '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No library found"* ]]
}

@test "malformed config falls back to cwd library" {
  printf 'not json {{{' > "$TEST_TMP/config.json"
  STACKS_CONFIG="$TEST_TMP/config.json" run bash -c "cd '$TEST_TMP/lib' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TMP/lib" ]
}

@test "expands a leading ~/ in the configured library path" {
  ln -s "$TEST_TMP/lib" "$HOME/.stacks-resolve-test-lib"
  printf '{"library": "~/.stacks-resolve-test-lib"}' > "$TEST_TMP/config.json"
  STACKS_CONFIG="$TEST_TMP/config.json" run bash "$SCRIPT"
  rm -f "$HOME/.stacks-resolve-test-lib"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.stacks-resolve-test-lib" ]
}
