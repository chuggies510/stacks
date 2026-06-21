#!/usr/bin/env bats

# lookup-misses.sh mines telemetry for /stacks:lookup misses (articles=="")
# whose searched stacks include the target stack, and emits them as enrichment
# gap rows: <TAB>{query}<TAB>lookup miss (empty slug — a miss has no article).

setup() {
  TEST_TMP=$(mktemp -d)
  LOG="$TEST_TMP/telemetry.jsonl"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/lookup-misses.sh"
  # rec <skill> <stacks> <articles> <query>
  rec() {
    jq -cn --arg s "$1" --arg st "$2" --arg a "$3" --arg q "$4" \
      '{ts:"t",session:"0",tool:"Skill",skill:$s,project:"p",query:$q,stacks:$st,articles:$a}' \
      >> "$LOG"
  }
}

teardown() { rm -rf "$TEST_TMP"; }

@test "a miss in the target stack is emitted as a gap row" {
  rec "stacks:lookup" "llm" "" "what is constrained decoding"
  run bash "$SCRIPT" llm "$LOG"
  [ "$status" -eq 0 ]
  [ "$output" = $'\twhat is constrained decoding\tlookup miss' ]
}

@test "a hit (articles populated) is NOT emitted" {
  rec "stacks:lookup" "llm" "Constrained Decoding" "what is constrained decoding"
  run bash "$SCRIPT" llm "$LOG"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a miss in a different stack is NOT emitted" {
  rec "stacks:lookup" "mep" "" "chilled water sizing"
  run bash "$SCRIPT" llm "$LOG"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "stack match is case-insensitive (LLM record, llm arg)" {
  rec "stacks:lookup" "LLM" "" "self refine loops"
  run bash "$SCRIPT" llm "$LOG"
  [ "$output" = $'\tself refine loops\tlookup miss' ]
}

@test "matches one stack inside a comma-separated searched set" {
  rec "stacks:lookup" "swe, llm" "" "generator verifier gap"
  run bash "$SCRIPT" llm "$LOG"
  [ "$output" = $'\tgenerator verifier gap\tlookup miss' ]
}

@test "identical miss queries dedup to one row" {
  rec "stacks:lookup" "llm" "" "llm as judge"
  rec "stacks:lookup" "llm" "" "llm as judge"
  run bash "$SCRIPT" llm "$LOG"
  [ "$(printf '%s\n' "$output" | grep -c 'llm as judge')" -eq 1 ]
}

@test "non-lookup skills are ignored even with empty articles" {
  rec "stacks:audit-stack" "llm" "" "audit run"
  run bash "$SCRIPT" llm "$LOG"
  [ -z "$output" ]
}

@test "a malformed JSON line is skipped, not fatal" {
  printf 'not json at all\n' >> "$LOG"
  rec "stacks:lookup" "llm" "" "valid miss"
  run bash "$SCRIPT" llm "$LOG"
  [ "$status" -eq 0 ]
  [ "$output" = $'\tvalid miss\tlookup miss' ]
}

@test "a tab inside the query is flattened so the row stays 3-field" {
  rec "stacks:lookup" "llm" "" $'tabby\tquery'
  run bash "$SCRIPT" llm "$LOG"
  [ "$status" -eq 0 ]
  # exactly two tabs in the emitted row (slug sep + reason sep), none from the query
  [ "$(printf '%s' "$output" | tr -cd '\t' | wc -c | tr -d ' ')" -eq 2 ]
}

@test "missing telemetry file exits clean with no output" {
  run bash "$SCRIPT" llm "$TEST_TMP/nope.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
