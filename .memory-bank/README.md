# Memory Bank

Memory bank answers one question: "What do I need to continue work that isn't derivable from CLAUDE.md, the codebase, git history, or GitHub issues?"

It is navigation state + archive index. Not reference documentation, not a version ledger, not an architecture guide.

## Files and Loading Tiers

| File | Tier | Loaded at /start | Purpose | Update frequency |
|------|------|:---:|---------|-----------------|
| project-brief.md | Always | Yes | What is this project, why does it exist, key constraints | Rarely (foundation) |
| active-context.md | Always | Yes | Session handoff, what's in flight, next priority | Every session (working state) |
| tech-context.md | On-demand | No | Reference: deploy scripts, commands, endpoints, cron jobs | Occasionally (when infra changes) |
| system-patterns.md | On-demand | No | Reference: architecture, flows, patterns | Occasionally (when architecture changes) |

This README is the formal spec. Not loaded into context. Both /start and /stop reference it.

## Exclusion Rules

| File | Excluded content |
|------|-----------------|
| project-brief.md | How-to-work rules (CLAUDE.md), session state, versions |
| active-context.md | Version tables, Files Modified lists, Test Status, architecture docs |
| tech-context.md | Version history, changelog accumulation, architecture explanations |
| system-patterns.md | Facts without context (tech-context), session state |

## No Version Tracking

Versions live in source files (plugin.json, package.json). No version tables in any memory bank file. /stop does not update version numbers. Read source files when you need a version.

## Governing Principles

- Don't store what a single tool call can recover
- Navigation state loads at start. Reference loads on demand.
- Handoffs serve two audiences: next session (continuity) and future archaeology (searchability)
- Current state = what's in flight, not what version is deployed

## Routing Guide for /stop

For each finding during impact analysis, route to:

1. **Is it about what just happened or what's next?** → active-context.md handoff
2. **Is it a stable reference fact (path, command, endpoint)?** → tech-context.md
3. **Does it show how systems connect?** → system-patterns.md
4. **Is it a trap future Claude would waste time on?** → CLAUDE.md gotcha
5. **Is it a scope/deliverable change?** → project-brief.md

Do NOT route git-derivable information (files modified, test pass counts, version bumps) to any memory bank file.

## project-brief.md Templates

**Codebase** (plugin/app repos): Mission, core requirements, key constraints, success metrics.

**Client project** (m2-clients/*): Client name, site address, contract scope, delivery timeline, deliverable type, building/asset list, phase definitions.

**Infrastructure** (homelab/config repos): Purpose, topology summary, service inventory, key constraints.
