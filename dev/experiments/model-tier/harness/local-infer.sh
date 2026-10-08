#!/usr/bin/env bash
# local-infer.sh <prompt-file> <output-file>
# local-infer.sh --model        print the model a call would use
# local-infer.sh --self-check
#
# Calls the local drafter, an OpenAI-compatible /v1/chat/completions server (the
# breathless vLLM, reached from the Mini through the 127.0.0.1:11436 tunnel; liminal
# tech-context owns its port, slots and speed). One user-role message; the prompt is
# read from a file and passed to jq via --rawfile, never string-interpolated into JSON.
#
# Every caller gets the model from STACKS_LOCAL_MODEL, never an argument. Thinking runs
# at medium effort with a 4,096-token budget inside a 16,384 output cap, the setting
# liminal measured on this server (S91): Qwen's default effort is xhigh, and an
# unbounded reply spent 8,149 of 8,192 tokens reasoning and returned nothing.
set -euo pipefail

STACKS_LOCAL_URL="${STACKS_LOCAL_URL:-http://127.0.0.1:11436}"
STACKS_LOCAL_MODEL="${STACKS_LOCAL_MODEL:-qwen3.8-27b}"
TEMP="${TEMP:-0}"
MAX_TOKENS="${MAX_TOKENS:-16384}"
# Optional: a bearer key for a hosted endpoint such as OpenRouter (the secrets vault
# decrypts it to ~/.config/secrets/openrouter.env), and a JSON object merged into the
# request last, for server-specific settings (thinking control, provider).
STACKS_LOCAL_KEY="${STACKS_LOCAL_KEY:-}"
STACKS_LOCAL_EXTRA="${STACKS_LOCAL_EXTRA:-{\}}"

call_local() {
  local promptfile="$1" outfile="$2" body resp content finish

  body=$(jq -n --arg model "$STACKS_LOCAL_MODEL" --rawfile prompt "$promptfile" \
    --argjson temp "$TEMP" --argjson max "$MAX_TOKENS" --argjson extra "$STACKS_LOCAL_EXTRA" \
    '{model:$model, messages:[{role:"user", content:$prompt}], stream:false,
      temperature:$temp, max_tokens:$max,
      reasoning_effort:"medium", thinking_token_budget:4096} * $extra')

  local auth=()
  [[ -z "$STACKS_LOCAL_KEY" ]] || auth=(-H "Authorization: Bearer $STACKS_LOCAL_KEY")

  if ! resp=$(curl -sS --max-time 600 -H 'Content-Type: application/json' ${auth[@]+"${auth[@]}"} \
      -X POST "$STACKS_LOCAL_URL/v1/chat/completions" -d "$body"); then
    echo "ERROR: request to $STACKS_LOCAL_URL/v1/chat/completions failed" >&2
    return 1
  fi
  [[ -n "$resp" ]] || { echo "ERROR: empty HTTP response (server down or timeout)" >&2; return 1; }

  content=$(printf '%s' "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null || true)
  finish=$(printf '%s' "$resp" | jq -r '.choices[0].finish_reason // empty' 2>/dev/null || true)

  # A reply cut at max_tokens is a partial article that would still look like one.
  [[ "$finish" == "stop" ]] || { echo "ERROR: finish_reason=${finish:-none} (truncated or failed). Raw: ${resp:0:500}" >&2; return 1; }
  [[ -n "$content" ]] || { echo "ERROR: empty .choices[0].message.content. Raw: ${resp:0:500}" >&2; return 1; }

  printf '%s' "$content" > "$outfile"
}

# The one place the default model lives; callers that log the model ask for it here.
if [[ "${1:-}" == "--model" ]]; then echo "$STACKS_LOCAL_MODEL"; exit 0; fi

if [[ "${1:-}" == "--self-check" ]]; then
  work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
  printf 'Reply with exactly: HARNESS-OK\n' > "$work/prompt.txt"
  if call_local "$work/prompt.txt" "$work/out.txt" && grep -qx 'HARNESS-OK' "$work/out.txt"; then
    echo "PASS: model=$STACKS_LOCAL_MODEL url=$STACKS_LOCAL_URL output=$(cat "$work/out.txt")"
    exit 0
  fi
  echo "FAIL: model=$STACKS_LOCAL_MODEL url=$STACKS_LOCAL_URL output=$(cat "$work/out.txt" 2>/dev/null)"
  exit 1
fi

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <prompt-file> <output-file>" >&2
  echo "       $0 --self-check" >&2
  exit 2
fi

call_local "$1" "$2"
