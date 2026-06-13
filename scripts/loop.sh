#!/usr/bin/env bash
# Scheduled library maintenance: run process-inbox then catalog stacks with pending files.
#
# Add to crontab (crontab -e):
#   0 * * * * PATH="$HOME/.local/bin:$HOME/.nvm/default/bin:/usr/local/bin:$PATH" \
#             bash /path/to/stacks/scripts/loop.sh
#
# Enable for a library:  touch "$LIBRARY/.loop-enabled"
# Disable:               rm "$LIBRARY/.loop-enabled"
#
# Note: 'claude' must be in PATH at cron time (see crontab PATH line above).
set -euo pipefail

CONFIG="${STACKS_CONFIG:-$HOME/.config/stacks/config.json}"
[[ -f "$CONFIG" ]] || { echo "[loop] no config at $CONFIG"; exit 0; }

LIBRARY=$(jq -r '.library // empty' "$CONFIG")
LIBRARY="${LIBRARY/#\~/$HOME}"
[[ -d "$LIBRARY" ]] || { echo "[loop] library not found: $LIBRARY"; exit 0; }

LOG="$LIBRARY/loop.log"
log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG"; }

[[ -f "$LIBRARY/.loop-enabled" ]] || { log "disabled (.loop-enabled absent)"; exit 0; }

mapfile -t inbox_files < <(find "$LIBRARY/inbox" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)
if [[ ${#inbox_files[@]} -eq 0 ]]; then
  log "inbox empty — no-op"
  exit 0
fi

log "routing ${#inbox_files[@]} inbox file(s) via process-inbox..."
cd "$LIBRARY"
claude -p "/stacks:process-inbox" >> "$LOG" 2>&1 \
  || log "process-inbox failed (see log above)"

cataloged=0
for stack_dir in "$LIBRARY"/*/; do
  [[ -f "${stack_dir}STACK.md" ]] || continue
  stack=$(basename "$stack_dir")
  count=$(find "${stack_dir}sources/incoming" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$count" -gt 0 ]]; then
    log "cataloging $stack ($count file(s))..."
    claude -p "/stacks:catalog-sources $stack" >> "$LOG" 2>&1 \
      || log "catalog-sources failed for $stack (see log above)"
    cataloged=$((cataloged + 1))
  fi
done

[[ "$cataloged" -eq 0 ]] && log "no stacks with incoming files after routing"
log "done"
