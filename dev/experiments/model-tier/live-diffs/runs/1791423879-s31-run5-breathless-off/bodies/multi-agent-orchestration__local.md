---
last_verified: ""
sources:
  - sources/arxiv/arxiv-2507.13334-context-engineering-survey.md
  - sources/zenml/zenml-2025-12-llmops-1200-deployments.md
  - sources/arxiv/benchmarking-open-ended-multi-agent-coordination.md
  - sources/arxiv/hallucination-as-context-drift.md
  - sources/incoming/anthropic-prompting-claude-opus-5.md
title: Multi-Agent Orchestration
routing: multi-agent systems — how to coordinate multiple LLM agents, route work between them, distribute context, and which protocols (MCP, A2A, ACP) handle inter-agent communication; also covers coordination-specific eval gaps, context drift as a hallucination cause at agent handoffs, and how to cap subagent delegation on Opus 5
tags:
  - llm
  - agents
  - multi-agent
  - orchestration
  - context-engineering
  - mcp
  - evals
  - hallucination
  - cost-economics
---

## Overview

Multi-agent orchestration is the set of mechanisms that coordinate multiple LLM-powered agents toward a shared task: routing work between them, distributing context so each agent sees what it needs, and keeping each agent's local view consistent with the evolving shared world state. It is distinct from single-agent design in that coordination quality becomes a first-class concern alongside individual model quality [arxiv-2507.13334-context-engineering-survey].

The orchestration layer specifically implements the dynamic-state component (c_state) of context engineering: the state of the user, world, or multi-agent system must be continuously assembled and distributed across all participating agents rather than held in one context window [arxiv-2507.13334-context-engineering-survey].

## Key concepts

**Coordination strategies** split into three broad patterns [arxiv-2507.13334-context-engineering-survey]:

- **Hierarchical orchestration**: a supervisor agent delegates sub-tasks to worker agents.
- **Consensus-based coordination**: agents vote or negotiate to reach agreement before acting.
- **Decentralized coordination**: peer-to-peer, no central planner.

**Context distribution** is the plumbing underneath all three patterns: orchestration mechanisms handle environmental state updates and adaptive responses so that each agent's local context stays consistent with shared world state as the task progresses [arxiv-2507.13334-context-engineering-survey].

## Communication protocols

Agent-to-agent communication spans a wide range, from legacy standards (KQML, FIPA ACL, designed for classical symbolic agents) to LLM-native frameworks that support natural language negotiation and collaborative reasoning between agents [arxiv-2507.13334-context-engineering-survey].

For large-scale future deployments, the field is converging on four emerging protocols for inter-agent communication and context distribution: MCP (Model Context Protocol), A2A (Agent-to-Agent), ACP (Agent Communication Protocol), and ANP (Agent Network Protocol) [arxiv-2507.13334-context-engineering-survey]. MCP has reached production adoption across a wide range of tooling [zenml-2025-12-llmops-1200-deployments]. A2A, ACP, and ANP are newer; the survey treats all four as emerging standards targeting large-scale future deployments, not a stable current baseline.

## Production patterns

Production teams tend to map multi-agent orchestration onto infrastructure they already operate rather than adopting purpose-built orchestration frameworks.

LinkedIn treats multi-agent coordination as a distributed microservices problem: inter-agent calls use existing messaging infrastructure and gRPC, the same stack that handles non-AI services [zenml-2025-12-llmops-1200-deployments]. Their GenAI rebuild focused engineering effort on capacity/latency tradeoffs, async non-blocking pipelines, and streaming response parsing [zenml-2025-12-llmops-1200-deployments].

DoorDash structures multi-agent work around three components: decomposers (break a task into sub-tasks), progress trackers (manage dependencies between sub-tasks), and persistent workspaces (shared artifact storage that agents read and write across the pipeline) [zenml-2025-12-llmops-1200-deployments].

Ramp's expense-approval pipeline pairs a policy agent handling over 65% of expense approvals autonomously, with explainable reasoning surfaced to the user, with uncertain cases routed to human review [zenml-2025-12-llmops-1200-deployments].

**Progressive autonomy** is the recurring deployment pattern across these case studies: start with AI producing suggestions (human reviews every output), then graduate high-confidence cases to autonomous action as the system proves reliable in the lower-stakes mode [zenml-2025-12-llmops-1200-deployments].

## Subagent delegation on Opus 5

Opus 5 delegates to subagents more readily than prior models [anthropic-prompting-claude-opus-5]. Delegation pays on genuinely independent, sizeable tracks of work but multiplies cost and time on small tasks [anthropic-prompting-claude-opus-5].

Control it with explicit guidance on which scenarios warrant delegation, or with deterministic caps on spawn count [anthropic-prompting-claude-opus-5]. The published example guidance: delegate only for large, genuinely independent, parallelizable tasks (e.g. a wide multi-file investigation); do not delegate work finishable in a handful of tool calls; do not use subagents to verify your own work; use one subagent rather than several if one suffices; keep spawn counts low [anthropic-prompting-claude-opus-5].

The model coordinates subagent teams well, with effective writer-verifier patterns and few cases of agents overwriting each other's work; cap delegation on cost-sensitive workloads [anthropic-prompting-claude-opus-5].

## Eval Strategy

Evaluating multi-agent systems requires two separate measurement layers, not just single-agent evals applied at scale [arxiv-2507.13334-context-engineering-survey]:

1. **Per-agent performance**: does each agent complete its delegated sub-task correctly?
2. **Coordination quality**: does the system as a whole produce consistent, non-duplicated, non-contradictory outputs? Does context distribution work across the boundary between agents?

Benchmarks designed for single-agent settings do not surface coordination failures (dropped state at handoffs, conflicting beliefs between agents, supervisor misjudging worker results). Separate benchmarks scoped to the coordination layer are needed. Existing multi-agent LLM benchmarks (MultiAgentBench, Collab-Overcooked, and related work) evaluate collaboration but typically in shorter-horizon, more narrowly specified tasks; other benchmarks test long-horizon completion in primarily single-agent settings, or include multiple agents without explicit, controllable coordination demands — no prior benchmark combined long-horizon, open-ended task structure with explicit, procedurally generated, controllable coordination difficulty [benchmarking-open-ended-multi-agent-coordination].

ALEM is a benchmark built to close that gap: a JAX-based, Craftax-like long-horizon survival world (exploration, crafting, trading, combat) with procedurally generated coordination tasks, soft specialisation, inter-agent communication, and a single parameter controlling coordination difficulty [benchmarking-open-ended-multi-agent-coordination]. Its coordination-coupling spectrum varies the temporal separation (Δt) between two agents' coupled actions across three regimes: long-range (large Δt — one agent's output is needed much later by a second agent), handover (small Δt — one agent initiates a task a second must complete within a short window), and synchronous (Δt = 0 — both agents must act on the same target at the same timestep) [benchmarking-open-ended-multi-agent-coordination].

Evaluating 13 modern LLMs zero-shot in homogeneous teams, with trained MARL (multi-agent reinforcement learning) agents as reference points, current LLM agents remain far from solving the benchmark, averaging only ~6% normalised return [benchmarking-open-ended-multi-agent-coordination]. Individual task competence does not imply coordination competence: on the hardest coordination setting, zero-shot Gemini-3.1-Pro-High performs comparably to MARL agents trained for one billion environment steps (17.5% vs. 17.6% coordination-reward), while GPT-5.4-High achieves strong base-task reward but much lower coordination reward — a model strong at the underlying task can still fail specifically at coordinating with teammates [benchmarking-open-ended-multi-agent-coordination]. Ablations show communication is the largest single contributor to coordination performance; memory and reasoning help only when used to maintain multi-step plans, not as general capability boosts [benchmarking-open-ended-multi-agent-coordination]. In initial heterogeneous-team experiments, mixed teams of different LLMs perform near the average of their constituent homogeneous baselines rather than matching the strongest member's performance — heterogeneity does not let a strong agent carry a weaker teammate [benchmarking-open-ended-multi-agent-coordination]. These results identify long-horizon, open-ended coordination as a bottleneck distinct from, and not predicted by, single-agent task capability [benchmarking-open-ended-multi-agent-coordination].

Agent harnesses, memory systems, and reinforcement learning show promising results in multi-agent settings but have not stabilized into consensus orchestration patterns as of late 2025 [zenml-2025-12-llmops-1200-deployments].

## Pitfalls

A significant class of multi-agent hallucinations arises not from model incapacity but from context drift: the divergence of internal knowledge states between concurrently operating agents. When agents enter a collaborative task with mismatched or stale representations of shared world state, correct individual reasoning can produce a collectively incorrect (hallucinated) joint output regardless of how good each agent is individually — the failure is in the interface, not the model [hallucination-as-context-drift]. Context drift occurs across three dimensions: spatial context (agents hold different beliefs about the same environment), temporal context (agents operate on information from different timestamps, one agent's "current" state is another's stale cache), and task context (agents accumulate different task histories, diverging on what has been decided, attempted, or ruled out) [hallucination-as-context-drift].

Existing hallucination mitigations — retrieval augmentation, self-consistency, calibration, and multi-agent debate — do not surface cross-agent context drift: when inconsistency arises from agents with genuinely different context histories, neither self-consistency nor debate exposes the underlying state mismatch, because each agent is internally consistent with its own (divergent) context [hallucination-as-context-drift]. A systematic empirical taxonomy of multi-agent failures (MAST), cataloguing 14 failure modes across 1,600+ annotated traces from seven agent frameworks (AutoGen, MetaGPT, LangGraph, CrewAI, AgentVerse, etc.), corroborates that inter-agent misalignment is a distinct, pervasive failure category separate from individual model errors [hallucination-as-context-drift].

Naive full-broadcast synchronization — propagating every agent's full state to every other agent — is itself a failure mode, termed the contamination effect: in controlled experiments (n=30/condition, travel-planning domain, 8 scenarios), full-broadcast synchronization increased hallucination rate by 34% over a no-sync baseline (HR 0.658 vs. 0.492, p=0.0022, d=1.18), because indiscriminate propagation of one agent's erroneous state contaminates the others [hallucination-as-context-drift]. This contamination effect is task-dependent, not universal: it did not replicate in a software-project-planning domain (n=10), where all synchronization conditions converged to a low hallucination rate (<0.2) — it appears specific to tasks where a single erroneous shared belief cascades across multiple evaluation dimensions (e.g., a wrong travel constraint propagating into itinerary, budget, and logistics judgments simultaneously) rather than being a general property of any inter-agent broadcast [hallucination-as-context-drift].

Two mitigations are proposed against the contamination pattern. The Context Divergence Score (CDS) is a lightweight pairwise scalar computed online from cosine distance between agent context embeddings, quantifying knowledge-state discrepancy across the spatial/temporal/task dimensions without requiring full context exchange, at O(nλ) overhead — cheap enough to run as a proactive drift-detection trigger rather than a post-hoc audit [hallucination-as-context-drift]. The Shared State Verification Protocol (SSVP) is a threshold-gated coordination protocol in which agents periodically exchange compressed state summaries and flag high-divergence conditions (CDS above threshold) before proceeding with joint reasoning, syncing only when needed rather than broadcasting continuously [hallucination-as-context-drift]. In the same travel-planning experiments, threshold-gated sync avoided the contamination failure mode while producing a modest, consistent hallucination reduction versus no-sync (HR 0.463, -5.9%, d=0.30) and a highly significant reduction versus full-broadcast (p=0.0005, d=1.47), using 58% fewer API calls than full-broadcast [hallucination-as-context-drift].

Distributed-systems state-consistency techniques (Lamport clocks, vector clocks, the CAP theorem) are well-studied for classical distributed systems and have been applied to robotic multi-agent systems, but their application to LLM agents — where "state" is unstructured natural language rather than a structured value — has received limited attention; this motivates treating multi-agent hallucination mitigation as a distributed-systems synchronization problem rather than a pure model-quality problem [hallucination-as-context-drift].

Hierarchical systems concentrate failure risk at the supervisor: if the supervisor's context becomes stale or overloaded, worker task decomposition degrades silently. Consensus and decentralized patterns distribute this risk but make failure observation harder.

## Sources

| Source | Tier | Notes |
|--------|------|-------|
| arxiv-2507.13334-context-engineering-survey | 2 | Survey of context engineering; covers c_state, coordination strategies, protocols, and eval framing |
| zenml-2025-12-llmops-1200-deployments | 3 | LLMOps Database case studies; covers LinkedIn, DoorDash, Ramp production patterns and progressive autonomy |
| benchmarking-open-ended-multi-agent-coordination | 2 | ALEM benchmark paper; coordination-scoped eval gap, coupling spectrum, 13-LLM results, ablations, heterogeneous-team results |
| hallucination-as-context-drift | 2 | Context-drift framing of multi-agent hallucination; CDS metric, SSVP protocol, contamination-effect experiments |
| anthropic-prompting-claude-opus-5 | 1 | Opus 5 prompting guide; subagent delegation behavior, cost/time tradeoff, and published delegation guidance |
