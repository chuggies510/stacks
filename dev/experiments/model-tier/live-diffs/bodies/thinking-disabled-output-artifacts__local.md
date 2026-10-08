---
last_verified: ""
sources:
  - sources/incoming/anthropic-prompting-claude-opus-5.md
title: Artifacts in Visible Output When Extended Thinking Is Disabled
routing: Artifacts in visible output when extended thinking is disabled — how to disable thinking, why disabling causes tool calls to leak as text and internal XML tags to appear in responses, and the specific prompt instructions to mitigate these failures
tags: [llm, prompt-engineering, tool-use, context-engineering]
---

## Overview

Extended thinking is on by default and can be disabled only at effort high or below [anthropic-prompting-claude-opus-5]. Disabling thinking introduces specific failure modes in visible output: tool calls appearing as plain text instead of structured blocks, and internal XML tags leaking into the response. The primary mitigation is to keep thinking enabled and control cost with lower effort; for most tasks, thinking enabled at low effort performs better than thinking disabled at similar cost [anthropic-prompting-claude-opus-5].

## Key Concepts

Two distinct failure modes occur when thinking is disabled:

1. **Tool calls as text**: The model occasionally writes a tool call into user-facing text instead of emitting a structured `tool_use` block. The turn completes normally and the call never runs; in agentic loops the leaked text stays in conversation history and affects later turns. This is most common on tool-heavy workloads such as search [anthropic-prompting-claude-opus-5].

2. **Internal XML tags in output**: The model can emit `<thinking>` or other internal XML tags into the visible response. A system-prompt rule telling the model not to think or reason increases tag leakage and should be removed [anthropic-prompting-claude-opus-5].

## Patterns

If thinking must stay disabled, one combined instruction mitigates both failure modes: say a brief sentence before a tool call; if no tool can express the request, say so instead of guessing; do not include internal or system XML tags in the response [anthropic-prompting-claude-opus-5].

Instructions that name thinking tags specifically are less effective than the general form, so avoid naming them [anthropic-prompting-claude-opus-5].

## Pitfalls

- A system-prompt rule telling the model not to think or reason increases tag leakage and should be removed [anthropic-prompting-claude-opus-5].
- Naming thinking tags specifically in instructions is less effective than the general form [anthropic-prompting-claude-opus-5].
- In agentic loops, leaked tool-call text stays in conversation history and affects later turns [anthropic-prompting-claude-opus-5].

## Cost & Latency

For most tasks, thinking enabled at low effort performs better than thinking disabled at similar cost [anthropic-prompting-claude-opus-5]. The recommended approach is to keep thinking enabled and control cost with lower effort rather than disabling thinking entirely [anthropic-prompting-claude-opus-5].
