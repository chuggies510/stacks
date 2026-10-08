---
last_verified: ""
sources:
  - sources/arxiv/arxiv-2507.13334-context-engineering-survey.md
  - sources/incoming/anthropic-prompting-claude-opus-5.md
title: Prompt Engineering
routing: prompt engineering techniques — zero-shot, few-shot, chain-of-thought, when each applies, why prompt engineering alone hits a ceiling that context engineering addresses, and how to tune prompts carried over to Claude Opus 5 (response length, narration, file verbosity, literal instruction following)
tags:
  - llm
  - prompt-engineering
  - chain-of-thought
  - reasoning
  - hallucination
---

## Overview

Prompt engineering is the practice of crafting text inputs to steer LLM behavior toward a desired output. It operates on the model's inherent capabilities without modifying weights, treating the instruction string as the primary control surface. The scope ranges from simple zero-shot directives to structured multi-step reasoning chains.

The paradigm has a documented ceiling. Prompt engineering treats context as a monolithic static string and relies on approximation-driven, subjective approaches that focus narrowly on task-specific optimization while neglecting individual LLM behavior [arxiv-2507.13334-context-engineering-survey]. This structural limitation, combined with model reliability issues (frequent hallucinations, unfaithfulness to input context, problematic sensitivity to input variations, and responses that appear syntactically correct while lacking semantic depth), is the core motivation for moving toward systematic context engineering [arxiv-2507.13334-context-engineering-survey]. See [[context-engineering]] for that successor paradigm.

## Key concepts

**Zero-shot prompting** relies on the model's inherent training to follow an instruction without demonstrations [arxiv-2507.13334-context-engineering-survey].

**Few-shot prompting** supplies carefully selected input-output examples alongside the instruction. Example selection matters: documented gains include 9.90% improvements in BLEU-4 for code summarization and 175.96% in exact match metrics for bug fixing, attributed to high-quality, task-aligned demonstrations [arxiv-2507.13334-context-engineering-survey].

**Chain-of-thought (CoT) prompting** decomposes complex reasoning into intermediate steps before the final answer. This enables complex multi-step reasoning and enhances element-aware summarization that integrates fine-grained source document details [arxiv-2507.13334-context-engineering-survey]. The mechanism is to elicit a scratchpad, not to post-process output.

**Superposition prompting** appears in the survey among context-engineering techniques: the survey attributes to techniques including RAG and superposition prompting documented gains such as an 18-fold improvement in text navigation accuracy and 94% success rates on targeted tasks [arxiv-2507.13334-context-engineering-survey].

**Cognitive architecture integration** represents advanced prompting frameworks that incorporate cognitive science principles into prompting strategies [arxiv-2507.13334-context-engineering-survey]. This sits at the boundary between prompt engineering and agent design.

## Patterns

**Select few-shot examples carefully, not randomly.** The documented performance gains (BLEU-4, exact match) are tied to "carefully selected" examples [arxiv-2507.13334-context-engineering-survey]. Random selection degrades below that ceiling.

**Use CoT when the task requires intermediate state.** Feeding the model a scratchpad structure ("think step by step" or a labeled chain) activates the gains reported for complex reasoning [arxiv-2507.13334-context-engineering-survey]. For single-lookup or classification tasks, CoT adds latency without benefit.

**Treat execution feedback as a prompt signal for code tasks.** Execution-aware debugging frameworks that pipe runtime error output back into the prompt achieve up to 9.8% improvements on code generation benchmarks [arxiv-2507.13334-context-engineering-survey]. This is prompt engineering applied iteratively inside a loop, not a single-shot pattern.

## Tuning prompts carried over to Claude Opus 5

Opus 5 performs well out of the box on prompts written for prior Opus models (Opus 4.8); the Anthropic prompting guide covers only the behavior deltas worth tuning when carrying a prompt over [anthropic-prompting-claude-opus-5].

**Response length.** Default user-facing responses run longer than on prior Opus models. The effort parameter controls how much the model thinks, not how much it says: lowering effort reduces thinking volume without reliably shortening the visible response. Response length must be controlled by prompting for it explicitly [anthropic-prompting-claude-opus-5]. A short conciseness instruction is effective ("Keep responses focused, brief, and concise… give a high-level summary unless an in-depth explanation is specifically requested"); in a long system prompt, pair it with a short reminder near the end (e.g. a `<tone_preference>` tag) [anthropic-prompting-claude-opus-5].

**Agentic narration.** The model narrates readily in agentic work — it announces what it is about to do, and per-message output is longer. Tune with explicit communication guidance: one sentence before the first tool call, brief updates only on an important finding or change of direction, and lead the final message with the outcome with supporting detail after it [anthropic-prompting-claude-opus-5]. Positive examples of the desired communication style tend to work better than instructions about what not to do [anthropic-prompting-claude-opus-5].

**File output.** Files written to disk (reports, Markdown, summaries) are also longer than on prior models, separate from conversational verbosity. Add explicit length calibration: match length to what the task needs, no filler sections, redundant summaries, or boilerplate [anthropic-prompting-claude-opus-5].

**Self-correction narration.** The model narrates corrections to its own earlier statements more than prior models. Mitigation: correct only when the error would change the user's code, conclusions, or decisions; state it plainly and briefly; for slips that change nothing, fix and move on without noting it [anthropic-prompting-claude-opus-5].

**Literal instruction following.** Instructions are followed literally: "only report high-severity issues" or "be conservative" in a code-review prompt makes the model report less, even though its extra findings are mostly real bugs. Ask for everything and filter in a separate pass [anthropic-prompting-claude-opus-5].

**Agentic task specification.** Agentic coding performs best when given the complete task specification up front and then left to run [anthropic-prompting-claude-opus-5].

**Re-validating prior-model workarounds.** Prompt-side workarounds (e.g. for vision) tuned for prior models should be re-validated on the new model; vision is strongest when the model has tools to iteratively analyze, crop, and verify, and tool use is a more cost-effective lever than thinking alone [anthropic-prompting-claude-opus-5].

## Pitfalls

**Sensitivity to input variation is a reliability hazard, not a tuning artifact.** LLMs show problematic sensitivity to input variations [arxiv-2507.13334-context-engineering-survey]. A prompt that works reliably on one phrasing may fail on superficially similar variants. Regression suites must cover surface-form variation, not just semantic variation.

**Syntactic correctness without semantic depth is a silent failure mode.** The survey names responses that appear syntactically correct while lacking semantic depth as a reliability issue [arxiv-2507.13334-context-engineering-survey]. Outputs that parse and format correctly are not a sufficient eval signal. Evals need semantic grading.

**Monolithic static strings don't scale with context complexity.** As task complexity grows, the static-string constraint becomes the binding limit: no retrieval, no dynamic injection, no structured memory [arxiv-2507.13334-context-engineering-survey]. The right response is to move to context engineering rather than to make the static string longer.

## Eval strategy

The empirical gains cited for few-shot (BLEU-4, exact match) reflect task-specific automatic metrics [arxiv-2507.13334-context-engineering-survey]. For code tasks, execution pass rate is the ground-truth signal; natural language tasks need semantic similarity or reference-based metrics rather than surface-level string match. Because prompt engineering is sensitive to input variation, eval sets should include paraphrased and reordered variants of the same semantic input to surface brittleness before deployment.

## Field notes

The most useful framing from the survey is the distinction between prompt engineering's ad-hoc, task-specific optimization and context engineering's systematic, model-aware approach [arxiv-2507.13334-context-engineering-survey]. In practice this means treating a well-tuned few-shot prompt as a component to be retired into a retrieval-backed or dynamically constructed context as soon as the task scope expands, rather than continuing to grow the static string.

The CoT gains on summarization (element-aware integration of fine-grained source details) are relevant to document-heavy workflows: structured reasoning chains outperform simple extraction prompts when the source material requires cross-document synthesis, not just locating a span.

## Sources

| Source | Tier | Notes |
|--------|------|-------|
| arxiv-2507.13334-context-engineering-survey | 2 | Peer-reviewed survey; covers prompt engineering as the predecessor paradigm to context engineering |
| anthropic-prompting-claude-opus-5 | 1 | Official Anthropic prompting guide for Claude Opus 5; documents behavior deltas and tuning guidance for carrying prompts from prior models |
