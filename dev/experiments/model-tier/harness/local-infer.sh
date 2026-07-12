#!/usr/bin/env bash
# local-infer.sh <model> <prompt-file> <output-file>
# local-infer.sh --self-check
#
# Calls Ollama's native /api/chat endpoint (NOT /v1, which drops num_ctx) with
# a single user-role message. Prompt is read from a file and passed to jq via
# --rawfile, never string-interpolated into JSON.
set -euo pipefail

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
TEMP="${TEMP:-0}"
NUM_CTX="${NUM_CTX:-16384}"

call_ollama() {
  local model="$1" promptfile="$2" outfile="$3"
  local body resp content

  body=$(jq -n --arg model "$model" --rawfile prompt "$promptfile" \
    --argjson temp "$TEMP" --argjson num_ctx "$NUM_CTX" \
    '{model:$model, messages:[{role:"user", content:$prompt}], stream:false,
      options:{temperature:$temp, num_ctx:$num_ctx}}')

  if ! resp=$(curl -sS --max-time 300 -X POST "$OLLAMA_URL/api/chat" -d "$body"); then
    echo "ERROR: curl request to $OLLAMA_URL/api/chat failed" >&2
    return 1
  fi

  if [[ -z "$resp" ]]; then
    echo "ERROR: empty HTTP response from Ollama (server down or timeout)" >&2
    return 1
  fi

  content=$(printf '%s' "$resp" | jq -r '.message.content // empty' 2>/dev/null || true)

  if [[ -z "$content" ]]; then
    echo "ERROR: empty/null .message.content (cold-load timeout under VRAM pressure, or model error). Raw response: $resp" >&2
    return 1
  fi

  printf '%s' "$content" > "$outfile"
}

if [[ "${1:-}" == "--self-check" ]]; then
  host="${OLLAMA_URL#http://}"
  model=$(OLLAMA_HOST="$host" ollama ps 2>/dev/null | awk 'NR==2{print $1}')
  if [[ -z "$model" ]]; then
    model=$(OLLAMA_HOST="$host" ollama list 2>/dev/null | awk 'NR==2{print $1}')
  fi
  if [[ -z "$model" ]]; then
    echo "FAIL: no model found via 'ollama ps' or 'ollama list'" >&2
    exit 1
  fi

  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  printf 'Reply with exactly: HARNESS-OK\n' > "$work/prompt.txt"

  echo "self-check: calling model '$model'" >&2
  if call_ollama "$model" "$work/prompt.txt" "$work/out.txt"; then
    if grep -q "HARNESS-OK" "$work/out.txt"; then
      echo "PASS: model=$model output=$(cat "$work/out.txt")"
      exit 0
    else
      echo "FAIL: sentinel HARNESS-OK not found. model=$model output=$(cat "$work/out.txt")"
      exit 1
    fi
  else
    echo "FAIL: inference call errored, see stderr above"
    exit 1
  fi
fi

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <model> <prompt-file> <output-file>" >&2
  echo "       $0 --self-check" >&2
  exit 2
fi

call_ollama "$1" "$2" "$3"
