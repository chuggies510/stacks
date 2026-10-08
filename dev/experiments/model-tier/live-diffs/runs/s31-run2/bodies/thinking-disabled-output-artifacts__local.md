---
last_verified: ""
sources:
  - sources/incoming/anthropic-prompting-claude-opus-5.md
title: Artifacts in Visible Output When Extended Thinking Is Disabled
routing: What artifacts appear in visible output when extended thinking is disabled, why tool calls leak as text, why internal XML tags appear, and what prompt instruction mitigates both
tags: [llm, prompt-engineering, tool-use, agents]
---

## Overview

When extended thinking is disabled on Claude, two artifact classes can appear in the visible response: tool calls written as plain text instead of structured blocks, and internal XML tags (such as `<thinking>`) leaking into user-facing output. Thinking is on by default and can be disabled only at effort high or below [anthropic-prompting-claude-opus-5]. The primary mitigation is to keep thinking enabled and control cost with a lower effort setting; for most tasks, thinking enabled at low effort performs better than thinking disabled at similar cost [anthropic-prompting-claude-opus-5].

## Key Concepts

**Tool calls as text.** The model occasionally writes a tool call into user-facing text instead of emitting a structured `tool_use` block. The turn completes normally and the call never runs; in agentic loops the leaked text stays in conversation history and affects later turns. This failure mode is most common on tool-heavy workloads such as search [anthropic-prompting-claude-opus-5].

**Internal XML tags in output.** The model can emit `<thinking>` or other internal XML tags into the visible response. A system-prompt rule telling the model not to think or reason increases tag leakage and should be removed [anthropic-prompting-claude-opus-5].

## Patterns

If thinking must stay disabled, one combined instruction mitigates both artifact classes: say a brief sentence before a tool call; if no tool can express the request, say so instead of guessing; do not include internal or system XML tags in the response [anthropic-prompting-claude-opus-5].

Instructions that name thinking tags specifically are less effective than the general form, so avoid naming them [anthropic-prompting-claude-opus-5].

## Pitfalls

A system-prompt rule that tells the model not to think or reason increases tag leakage rather than suppressing it and should be removed [anthropic-prompting-claude-opus-5].

In agentic loops, a leaked tool-call-as-text does not fail loudly: the turn completes, the call never executes, and the stray text persists in conversation history, affecting later turns [anthropic-prompting-claude-opus-5].

## Cost & Latency

For most tasks, thinking enabled at low effort performs better than thinking disabled at similar cost [anthropic-prompting-claude-opus-5].
