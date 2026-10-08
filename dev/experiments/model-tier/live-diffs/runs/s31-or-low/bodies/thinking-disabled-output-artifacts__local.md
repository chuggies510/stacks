---
last_verified: ""
sources:
  - sources/incoming/anthropic-prompting-claude-opus-5.md
title: Artifacts in Visible Output When Extended Thinking Is Disabled
routing: Leaked tool calls and stray thinking XML tags in visible output when extended thinking is turned off, why a tool call shows up as text and never runs, why the model emits thinking tags, whether to disable thinking, and the prompt wording that mitigates both
tags: [llm, prompt-engineering]
---

## Overview

Extended thinking is on by default in Claude Opus 5 and can be disabled only at effort high or below [anthropic-prompting-claude-opus-5]. The primary mitigation for the output artifacts that appear when thinking is disabled is to keep thinking enabled and control cost with a lower effort setting; for most tasks, thinking enabled at low effort performs better than thinking disabled at similar cost [anthropic-prompting-claude-opus-5].

## Key Concepts

Two failure modes appear when extended thinking is disabled:

**Tool calls as text.** The model occasionally writes a tool call into user-facing text instead of emitting a structured `tool_use` block. The turn completes normally and the call never runs; in agentic loops the leaked text stays in conversation history and affects later turns. This is most common on tool-heavy workloads such as search [anthropic-prompting-claude-opus-5].

**Internal XML tags in output.** The model can emit `<thinking>` or other internal XML tags into the visible response [anthropic-prompting-claude-opus-5].

## Patterns

If thinking must stay disabled, one combined instruction mitigates both failure modes: say a brief sentence before a tool call; if no tool can express the request, say so instead of guessing; do not include internal or system XML tags in the response [anthropic-prompting-claude-opus-5].

## Pitfalls

A system-prompt rule telling the model not to think or reason increases tag leakage and should be removed [anthropic-prompting-claude-opus-5]. Instructions that name thinking tags specifically are less effective than the general form, so avoid naming them [anthropic-prompting-claude-opus-5].

## Cost & Latency

For most tasks, thinking enabled at low effort performs better than thinking disabled at similar cost [anthropic-prompting-claude-opus-5].
