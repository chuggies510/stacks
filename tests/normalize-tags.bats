#!/usr/bin/env bats

setup() {
  TEST_TMP=$(mktemp -d)
  STACK="$TEST_TMP/hvac"
  mkdir -p "$STACK/articles"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/normalize-tags.sh"
  cat > "$STACK/STACK.md" <<'EOF'
# hvac

## Tag Vocabulary

allowed_tags:
  - airflow
  - controls
EOF
}

teardown() { rm -rf "$TEST_TMP"; }

@test "block-list frontmatter tags in vocabulary pass" {
  cat > "$STACK/articles/vav.md" <<'EOF'
---
title: VAV Box
tags:
  - airflow
---
Body.
EOF
  run bash "$SCRIPT" "$STACK"
  [ "$status" -eq 0 ]
}

@test "inline flow-list frontmatter tags in vocabulary pass" {
  cat > "$STACK/articles/econ.md" <<'EOF'
---
title: Economizer
tags: [airflow, controls]
---
Body.
EOF
  run bash "$SCRIPT" "$STACK"
  [ "$status" -eq 0 ]
}

@test "quotes and trailing comments are stripped from allowed_tags entries" {
  cat > "$STACK/STACK.md" <<'EOF'
# hvac

allowed_tags:
  - "airflow"  # exhaust and supply
  - 'controls'
EOF
  cat > "$STACK/articles/vav.md" <<'EOF'
---
title: VAV Box
tags:
  - airflow
  - controls
---
Body.
EOF
  run bash "$SCRIPT" "$STACK"
  [ "$status" -eq 0 ]
}

@test "out-of-vocabulary tag halts with TAG_DRIFT on stderr and exit 1" {
  cat > "$STACK/articles/vav.md" <<'EOF'
---
title: VAV Box
tags:
  - refrigerant
---
Body.
EOF
  run bash "$SCRIPT" "$STACK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"TAG_DRIFT: vav: refrigerant"* ]]
}

@test "closing frontmatter fence is not misparsed as a tag item" {
  # The tags: block ends right at the closing '---'; the fence line itself
  # starts with '-' and would match the tag-item pattern if the fm_count
  # exit rule didn't intercept it first. A phantom '-' or '--' tag must
  # never be reported as drift.
  cat > "$STACK/articles/vav.md" <<'EOF'
---
title: VAV Box
tags:
  - airflow
---
Body.
EOF
  run bash "$SCRIPT" "$STACK"
  [ "$status" -eq 0 ]
  [[ "$output" != *"TAG_DRIFT"* ]]
}

@test "missing allowed_tags skips the drift check (backward compat)" {
  cat > "$STACK/STACK.md" <<'EOF'
# hvac

No tag vocabulary section here.
EOF
  cat > "$STACK/articles/vav.md" <<'EOF'
---
title: VAV Box
tags:
  - anything-goes
---
Body.
EOF
  run bash "$SCRIPT" "$STACK"
  [ "$status" -eq 0 ]
}
