#!/usr/bin/env bash
set -euo pipefail

# Shard a newline-delimited list file into fixed-size batch files.
#
# Usage:
#   bash shard-batches.sh <list_file> <batch_size> <out_prefix>
#
# Arguments:
#   list_file    Path to a newline-delimited input file (e.g. article or source
#                paths, one per line).  Empty lines are included in the count.
#   batch_size   Maximum number of lines per shard (positive integer).
#   out_prefix   Output file prefix including directory and filename stem.
#                Shard N is written to <out_prefix><NN>.txt where NN is
#                zero-padded to two digits (00, 01, ...).
#
# Output files:
#   <out_prefix>00.txt, <out_prefix>01.txt, ...
#
# The output filename format (two-digit zero-padded numeric suffix + .txt) must
# match the pattern the calling skill uses when it globs for the shard files
# (e.g. _a1-batch-*.txt).  Callers pass e.g.:
#   "$STACK/dev/audit/_a1-batch-"    -> produces _a1-batch-00.txt, _a1-batch-01.txt ...
#   "$STACK/dev/audit/_a2-batch-"    -> produces _a2-batch-00.txt, _a2-batch-01.txt ...
#   "$STACK/dev/audit/_a3-batch-"    -> produces _a3-batch-00.txt, _a3-batch-01.txt ...

if [[ $# -ne 3 ]]; then
  echo "usage: shard-batches.sh <list_file> <batch_size> <out_prefix>" >&2
  exit 1
fi

list_file=$1
batch_size=$2
out_prefix=$3

# Use bare `print` (defaults to $0 + ORS) — never `$0` literal in the awk
# script, because the skill harness substitutes shell `$N` positionals through
# skill args.
awk -v bs="$batch_size" -v prefix="$out_prefix" '
  { batch = int((NR-1)/bs); print > sprintf("%s%02d.txt", prefix, batch) }
' "$list_file"
