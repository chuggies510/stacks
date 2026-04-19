#!/usr/bin/env bash
set -euo pipefail

# Reads an input string from stdin and emits a sha256 digest (64 hex chars + newline).
# Callers in W1b pipe `echo -n "{sorted-source-paths}|{slug}"` (paths joined by
# `|`, then a trailing `|`, then the slug) so the hash is stable across runs.
# No filename suffix is emitted (awk strips the `  -`).

sha256sum | awk '{print $1}'
