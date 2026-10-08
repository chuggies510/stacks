---
last_verified: ""
sources:
  - sources/incoming/anthropic-prompting-claude-opus-5.md
title: Artifacts in Visible Output When Extended Thinking Is Disabled
routing: What goes wrong in visible output when extended thinking is disabled, tool calls leaking as plain text, internal XML tags in responses, how to mitigate with prompt instructions, whether to keep thinking on at lower effort instead
tags: [llm, prompt-engineering, tool-use, structured-output, cost-economics]
---

## Overview

Extended thinking is on by default in Claude Opus 5 and can be disabled only at effort high or below [anthropic-prompting-claude-opus-5]. When thinking is disabled, two artifact types can appear in the visible output: tool calls written as plain text and internal XML tags leaking into the response [anthropic-prompting-claude-opus-5].

## Key Concepts

### Tool calls as text

With thinking disabled, the model occasionally writes a tool call into user-facing text instead of emitting a structured `tool_use` block [anthropic-prompting-claude-opus-5]. The turn completes normally and the call never runs [anthropic-prompting-claude-opus-5]. In agentic loops, the leaked text stays in conversation history and affects later turns [anthropic-prompting-claude-opus-5]. This is most common on tool-heavy workloads such as search [anthropic-prompting-claude-opus-5].

### Internal XML tags in output

The model can emit `<thinking>` or other internal XML tags into the visible response [anthropic-prompting-claude-opus-5].

## Patterns

### Primary mitigation: keep thinking enabled

The primary mitigation is to keep thinking enabled and control cost with lower effort settings (see [[llm-cost-control-production]] for effort configuration) [anthropic-prompting-claude-opus-5]. For most tasks, thinking enabled at low effort performs better than thinking disabled at similar cost [anthropic-prompting-claude-opus-5].

### Combined prompt instruction when thinking must stay disabled

If thinking must stay disabled, one combined instruction mitigates both artifact types: say a brief sentence before a tool call; if no tool can express the request, say so instead of guessing; do not include internal or system XML tags in the response [anthropic-prompting-claude-opus-5].

## Pitfalls

- A system-prompt rule telling the model not to think or reason increases tag leakage and should be removed [anthropic-prompting-claude-opus-5].
- Instructions that name thinking tags specifically are less effective than the general form; avoid naming them [anthropic-prompting-claude-opus-5].
