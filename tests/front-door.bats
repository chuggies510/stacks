#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/.."

@test "lookup routing instructions are zsh-safe" {
  run grep -nE 'mapfile|reference/\*/index\.md' "$ROOT/skills/lookup/SKILL.md"
  [ "$status" -eq 1 ]

  snippet=$(awk '/^STACKS_TO_SEARCH=/{copy=1} copy && /^```/{exit} copy{print}' "$ROOT/skills/lookup/SKILL.md")
  run zsh -c 'set -e; LIBRARY=$1; mkdir -p "$LIBRARY/a/reference"; printf "%s\n" "- [A](a/)" > "$LIBRARY/catalog.md"; eval "$2"; printf "%s\n" "$STACKS_TO_SEARCH"; find "$LIBRARY/a/reference" -mindepth 2 -maxdepth 2 -type f -name index.md -print' _ "$BATS_TEST_TMPDIR/library" "$snippet"
  [ "$status" -eq 0 ]
  [ "$output" = "a" ]
}

@test "using-stacks routes every installed operational skill" {
  front="$ROOT/skills/using-stacks/SKILL.md"
  checks=0
  for dir in "$ROOT"/skills/*; do
    name="${dir##*/}"
    [ "$name" = using-stacks ] && continue
    grep -q "→ $name" "$front"
    checks=$((checks + 1))
  done
  [ "$checks" -eq 8 ]
}
