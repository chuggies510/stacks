#!/usr/bin/env bats
# The frontmatter list reader and its writer twin (scripts/article-field.sh).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=../scripts/article-field.sh
  source "$ROOT/scripts/article-field.sh"
  A="$BATS_TEST_TMPDIR/a.md"
}

@test "article_list reads both list styles and stops at the closing delimiter" {
  printf -- '---\ntags: [a, "b"]\nsources:\n  - s/1.md\n  - s/2.md\n---\nsources:\n- body\n' > "$A"
  [ "$(article_list tags "$A" | tr '\n' '|')" = "a|b|" ]
  [ "$(article_list sources "$A" | tr '\n' '|')" = "s/1.md|s/2.md|" ]
}

@test "article_set_list replaces either style, adds a missing field, and leaves the body alone" {
  printf -- '---\ntitle: T\ntags: [a, b]\nsources:\n  - old.md\nrouting: r\n---\nsources:\n- body bullet\n' > "$A"
  printf 'new1.md\nnew2.md\n' | article_set_list sources "$A"
  printf 'b\n' | article_set_list tags "$A"
  printf 'x\n' | article_set_list extra "$A"
  [ "$(cat "$A")" = "$(printf -- '---\ntitle: T\ntags:\n  - b\nsources:\n  - new1.md\n  - new2.md\nrouting: r\nextra:\n  - x\n---\nsources:\n- body bullet')" ]
}

@test "article_set_list refuses unclosed frontmatter and leaves the file unchanged" {
  printf -- '---\ntags: [a]\nno closing line\n' > "$A"
  run bash -c "source '$ROOT/scripts/article-field.sh'; printf 'b\n' | article_set_list tags '$A'"
  [ "$status" -ne 0 ]
  [ "$(cat "$A")" = "$(printf -- '---\ntags: [a]\nno closing line')" ]
}
