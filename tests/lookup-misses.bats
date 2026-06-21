#!/usr/bin/env bats

# lookup-misses.sh mines telemetry for /stacks:lookup misses (articles=="")
# whose searched stacks include the target stack, and emits them as enrichment
# gap rows: lookup-miss<TAB>{query}<TAB>lookup miss (sentinel slug — a miss has
# no home article, and an empty leading field can't survive read/IFS=$'\t').

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
  [ "$output" = $'lookup-miss\twhat is constrained decoding\tlookup miss' ]
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
  [ "$output" = $'lookup-miss\tself refine loops\tlookup miss' ]
}

@test "matches one stack inside a comma-separated searched set" {
  rec "stacks:lookup" "swe, llm" "" "generator verifier gap"
  run bash "$SCRIPT" llm "$LOG"
  [ "$output" = $'lookup-miss\tgenerator verifier gap\tlookup miss' ]
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
  [ "$output" = $'lookup-miss\tvalid miss\tlookup miss' ]
}

@test "a tab inside the query is flattened so the row stays 3-field" {
  rec "stacks:lookup" "llm" "" $'tabby\tquery'
  run bash "$SCRIPT" llm "$LOG"
  [ "$status" -eq 0 ]
  # exactly two tabs in the emitted row (slug sep + reason sep), none from the query
  [ "$(printf '%s' "$output" | tr -cd '\t' | wc -c | tr -d ' ')" -eq 2 ]
}

@test "emitted row survives a read/IFS=tab round-trip (slug is the sentinel, not the query)" {
  # The empty-leading-slug form gets mangled by `read` (a leading tab is stripped
  # as IFS whitespace), shifting the query into the slug. The sentinel prevents it.
  rec "stacks:lookup" "llm" "" "round trip query"
  run bash "$SCRIPT" llm "$LOG"
  IFS=$'\t' read -r slug claim reason <<< "$output"
  [ "$slug" = "lookup-miss" ]
  [ "$claim" = "round trip query" ]
  [ "$reason" = "lookup miss" ]
}

@test "missing telemetry file exits clean with no output" {
  run bash "$SCRIPT" llm "$TEST_TMP/nope.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
