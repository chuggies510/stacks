---
last_verified: ""
sources:
  - sources/incoming/anthropic-prompting-claude-opus-5.md
title: Artifacts in Visible Output When Extended Thinking Is Disabled
routing: Artifacts in visible output when extended thinking is disabled, why tool calls appear as text, why internal XML tags leak, how to mitigate with prompt wording, and whether to disable thinking
tags: [llm, prompt-engineering, tool-use, context-engineering]
---

## Overview

When extended thinking is disabled, the model can produce two types of artifacts in user-facing output: tool calls written as plain text instead of structured blocks, and internal XML tags leaking into the visible response [anthropic-prompting-claude-opus-5]. Thinking is on by default and can be disabled only at effort high or below [anthropic-prompting-claude-opus-5].

## Key Concepts

The primary mitigation is to keep thinking enabled and control cost with lower effort; for most tasks, thinking enabled at low effort performs better than thinking disabled at similar cost [anthropic-prompting-claude-opus-5].

## Patterns

If thinking must stay disabled, one combined instruction mitigates both artifact types: say a brief sentence before a tool call; if no tool can express the request, say so instead of guessing; do not include internal or system XML tags in the response [anthropic-prompting-claude-opus-5].

Instructions that name thinking tags specifically are less effective than the general form, so avoid naming them [anthropic-prompting-claude-opus-5].

## Pitfalls

**Tool calls as text:** The model occasionally writes a tool call into user-facing text instead of emitting a structured `tool_use` block. The turn completes normally and the call never runs; in agentic loops the leaked text stays in conversation history and affects later turns. This is most common on tool-heavy workloads such as search [anthropic-prompting-claude-opus-5].

**Internal XML tags in output:** The model can emit `<thinking>` or other internal XML tags into the visible response. A system-prompt rule telling the model not to think or reason increases tag leakage and should be removed [anthropic-prompting-claude-opus-5].
