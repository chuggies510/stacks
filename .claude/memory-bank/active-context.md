---
session: 27
machine: breathless
---

# Active Context

## Live constraints
- The Agent tool cannot dispatch local models (reaches only sonnet/haiku/opus/fable); the local-worker harness is **pal MCP `chat`** with a local model name — confirmed S25: pal is configured against `http://localhost:11434/v1` (Ollama) with 50 local models, so `read source → pal chat(model=<local>) → write gate file` works without the Agent tool. A bash+curl-to-`:11434` worker is the alternative harness (deterministic, no MCP/agent). (as-of: 2026-07-12) (rode: S22, S23, S24, S25, S26)
- liminal is the peer Claude session (local-LLM / fine-tuning expert), co-located on this host (3900x) at `~/chungus/dev/liminal`; it serves + scores local models on the shared RTX 3090 (SHARED with liminal's curator cron at :13 every 6h — during its training windows it evicts resident models, so gate heavy local calls on `nvidia-smi --query-gpu=memory.free` and keep pilot models warm via keep-alive). Locate its pane by NAME (windows renumber between sessions): `tmux list-panes -a -F '#{window_name} #{pane_id}' | awk '$1=="liminal"{print $2}'` (S25: pane `%47`). **Walkie-talkie send/verify/metachar-escape/return-path mechanics are canonical in `reference.md#cross-session-coordination` (dev bindings, dev.md § Worktrees & concurrent sessions points at it) — follow that, do NOT restate it here.** (as-of: 2026-07-12) (rode: S22, S23, S24, S25, S26)
- The `dev/experiments/model-tier/` dir (epic #109) is the first-class model-tier test area. **All four pipeline stages now have an offline gold-set benchmark** (extraction, synthesis, validation, enrichment); front-door `README.md` maps them. Local scoring by liminal + the live layers (enrich search-recall, validator shadow test) are the remaining epic work. (as-of: 2026-07-11) (rode: S22, S23, S24, S25, S26)

## Open thread
None open. (S27, breathless, 2026-07-23) Validation stays cloud-owned (final, S26). Since the S26 handoff, un-recorded sessions shipped the always-on haiku A/B synthesis self-test (v0.67.0 → v0.68.3) and enforced routing at the catalog/enrich/audit gates (#117 #114 #100). Freshest live signal is a 4-bug source→article→lookup fidelity cluster filed 07-16..07-18: thin/wrong sources in (#115 PDF drop, #116 arXiv abstract-only), silently-wrong lookups out (#118 wrong edition, #119 partial answer reads complete). None triaged to high priority.

## Next priority
| # | Item | Note |
|---|------|------|
| #115 | fetch-source-text.sh can't stage a PDF | canonical papers dropped; root of the cluster |
| #116 | arXiv /abs/ stages abstract-only | thin article passes every gate |
| #118 #119 | lookup fidelity | wrong edition; partial answer reads complete |
| #113 | retire dead Step 4.5 shadow | validation now cloud-owned; cheap cleanup |
| #109 | synthesis at-scale measurement | epic (ADR-002); same faithfulness wall likely |
| — | backlog | #120 #112 #111 #102 #95 #70 #63 |

**Cross-repo follow-up:** the ~71 verifier-confirmed overstatements live in `library-stack/llm/articles/` (a separate repo), not here. #120 wants non-Anthropic tiers (OpenRouter/local qwen) into the A/B harness — the local-worker constraint above is the relevant infra. Diverse-fleet precision lead (if validation ever reopens): `dev/experiments/model-tier/results-liminal-S63-minicheck-atomic.md`.
