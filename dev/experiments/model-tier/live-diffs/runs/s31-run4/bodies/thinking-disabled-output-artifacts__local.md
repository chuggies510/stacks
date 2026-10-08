---
last_verified: ""
sources:
  - sources/incoming/anthropic-prompting-claude-opus-5.md
title: Artifacts in Visible Output When Extended Thinking Is Disabled
routing: What happens when you disable extended thinking on Claude — leaked tool calls as text, stray thinking XML tags in output, whether to disable thinking at all, and the prompt wording that mitigates both artifacts
tags: [llm, prompt-engineering, reasoning]
---

## Overview

Extended thinking is on by default and can be disabled only at effort high or below [anthropic-prompting-claude-opus-5]. When thinking is disabled, two artifact types can appear in the visible output: tool calls written as plain text, and internal XML tags leaking into the response [anthropic-prompting-claude-opus-5].

## Key Concepts

**Tool calls as text.** The model occasionally writes a tool call into user-facing text instead of emitting a structured `tool_use` block. The turn completes normally and the call never runs; in agentic loops the leaked text stays in conversation history and affects later turns. This is most common on tool-heavy workloads such as search [anthropic-prompting-claude-opus-5].

**Internal XML tags in output.** The model can emit `<thinking>` or other internal XML tags into the visible response. A system-prompt rule telling the model not to think or reason increases tag leakage and should be removed [anthropic-prompting-claude-opus-5].

## Patterns

**Primary mitigation: keep thinking enabled.** For most tasks, thinking enabled at low effort performs better than thinking disabled at similar cost; the recommended approach is to keep thinking on and control cost with a lower effort setting [anthropic-prompting-claude-opus-5].

**If thinking must stay disabled.** One combined instruction mitigates both artifact types: say a brief sentence before a tool call; if no tool can express the request, say so instead of guessing; do not include internal or system XML tags in the response [anthropic-prompting-claude-opus-5].

## Pitfalls

Instructions that name thinking tags specifically are less effective than the general form, so avoid naming them [anthropic-prompting-claude-opus-5].
