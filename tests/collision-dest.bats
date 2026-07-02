#!/usr/bin/env bats

setup() {
  TEST_TMP=$(mktemp -d)
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/collision-dest.sh"
}

teardown() { rm -rf "$TEST_TMP"; }

@test "no collision returns the plain path" {
  run bash "$SCRIPT" "$TEST_TMP" "file.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TMP/file.txt" ]
}

@test "existing file gets a -1 suffix before the extension" {
  touch "$TEST_TMP/file.txt"
  run bash "$SCRIPT" "$TEST_TMP" "file.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_TMP/file-1.txt" ]
}

@test "counter increments past multiple existing collisions" {
  touch "$TEST_TMP/file.txt" "$TEST_TMP/file-1.txt" "$TEST_TMP/file-2.txt"
  run bash "$SCRIPT" "$TEST_TMP" "file.txt"
  [ "$output" = "$TEST_TMP/file-3.txt" ]
}

@test "extension-less filename collides without a stray dot" {
  touch "$TEST_TMP/README"
  run bash "$SCRIPT" "$TEST_TMP" "README"
  [ "$output" = "$TEST_TMP/README-1" ]
}

@test "wrong arg count exits 1 with a usage message" {
  run bash "$SCRIPT" "$TEST_TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage:"* ]]
}
