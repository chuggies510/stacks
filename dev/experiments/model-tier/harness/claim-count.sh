#!/usr/bin/env bash
# claim-count.sh <concept-block-file>
# Prints the number of claim bullets under a concept block's `### Claims` heading.
# The single definition shared by the drafter's refusal gate and the advisory
# summary's population check, so the two can never count differently.
awk '/^###[[:space:]]*Claims/{f=1;next} f&&/^[[:space:]]*-[[:space:]]/{c++} END{print c+0}' "${1:?Usage: claim-count.sh <concept-block-file>}"
