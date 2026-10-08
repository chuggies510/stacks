---
last_verified: ""
sources:
  - sources/incoming/anthropic-prompting-claude-opus-5.md
title: Artifacts in Visible Output When Extended Thinking Is Disabled
routing: Artifacts in visible output when extended thinking is disabled, why tool calls appear as text, why internal XML tags leak, how to mitigate with prompt instructions, and whether to disable thinking
tags: [llm, prompt-engineering, tool-use, context-engineering]
---

## Overview

Extended thinking is on by default and can be disabled only at effort high or below [anthropic-prompting-claude-opus-5]. Disabling thinking can introduce artifacts in the visible output, including tool calls rendered as text and internal XML tags leaking into the response [anthropic-prompting-claude-opus-5]. This article covers the specific failure modes that occur when thinking is disabled and the prompt-level mitigations that reduce them.

## Key Concepts

The primary mitigation for these artifacts is to keep thinking enabled and control cost with lower effort; for most tasks, thinking enabled at low effort performs better than thinking disabled at similar cost [anthropic-prompting-claude-opus-5]. If thinking must remain disabled, specific prompt instructions can mitigate the two main failure modes [anthropic-prompting-claude-opus-5].

## Patterns

When thinking is disabled, a combined instruction mitigates both failure modes: say a brief sentence before a tool call; if no tool can express the request, say so instead of guessing; do not include internal or system XML tags in the response [anthropic-prompting-claude-opus-5]. Instructions that name thinking tags specifically are less effective than the general form, so avoid naming them [anthropic-prompting-claude-opus-5].

## Pitfalls

**Tool calls as text:** The model occasionally writes a tool call into user-facing text instead of emitting a structured `tool_use` block. The turn completes normally and the call never runs; in agentic loops the leaked text stays in conversation history and affects later turns. This is most common on tool-heavy workloads such as search [anthropic-prompting-claude-opus-5].

**Internal XML tags in output:** The model can emit `<thinking>` or other internal XML tags into the visible response. A system-prompt rule telling the model not to think or reason increases tag leakage and should be removed [anthropic-prompting-claude-opus-5].

## Field Notes

For most tasks, thinking enabled at low effort performs better than thinking disabled at similar cost, making the default configuration the preferred choice unless there is a specific reason to disable thinking [anthropic-prompting-claude-opus-5].
