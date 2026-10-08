---
last_verified: ""
updated: 2026-10-07
sources:
  - sources/incoming/anthropic-prompting-claude-opus-5.md
title: Artifacts in Visible Output When Extended Thinking Is Disabled
routing: Leaked tool calls and stray thinking XML tags in visible output when extended thinking is turned off — why a tool call shows up as text and never runs, why the model emits thinking tags, whether to disable thinking, and the prompt wording that mitigates both
tags:
  - llm
  - reasoning
  - tool-use
  - prompt-engineering
---

## Overview

Anthropic's prompting guide for Claude Opus 5 describes two failure modes that appear in the visible response when extended thinking is disabled [anthropic-prompting-claude-opus-5]. This article covers those two artifacts and the guide's mitigations. For the tool call and result loop itself, see [[tool-integrated-reasoning]].

## Key Concepts

- Thinking is on by default. It can be disabled only at effort high or below [anthropic-prompting-claude-opus-5].
- The guide's primary mitigation is to keep thinking enabled and control cost with lower effort. For most tasks, thinking enabled at low effort performs better than thinking disabled at similar cost [anthropic-prompting-claude-opus-5].

## Pitfalls

**Tool calls written as text.** The model occasionally writes a tool call into user-facing text instead of emitting a structured `tool_use` block [anthropic-prompting-claude-opus-5].
- The turn completes normally and the call never runs [anthropic-prompting-claude-opus-5].
- In agentic loops the leaked text stays in conversation history and affects later turns [anthropic-prompting-claude-opus-5].
- The guide says this is most common on tool-heavy workloads such as search [anthropic-prompting-claude-opus-5].

**Internal XML tags in output.** The model can emit `<thinking>` or other internal XML tags into the visible response [anthropic-prompting-claude-opus-5].
- A system-prompt rule telling the model not to think or reason increases tag leakage. The guide says to remove such a rule [anthropic-prompting-claude-opus-5].

## Patterns

If thinking must stay disabled, the guide gives one combined instruction that mitigates both failure modes [anthropic-prompting-claude-opus-5]:

- Say a brief sentence before a tool call.
- If no tool can express the request, say so instead of guessing.
- Do not include internal or system XML tags in the response.

Instructions that name thinking tags specifically are less effective than the general form, so the guide says to avoid naming them [anthropic-prompting-claude-opus-5].

## Sources

- anthropic-prompting-claude-opus-5 (tier 1, vendor documentation)
