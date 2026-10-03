---
session: 30
machine: mbp
---

# Active Context

## Live constraints
- The Agent tool cannot dispatch local models (reaches only sonnet/haiku/opus/fable); the local-worker harness is **pal MCP `chat`** with a local model name — confirmed S25: pal is configured against `http://localhost:11434/v1` (Ollama) with 50 local models, so `read source → pal chat(model=<local>) → write gate file` works without the Agent tool. A bash+curl-to-`:11434` worker is the alternative harness (deterministic, no MCP/agent). (as-of: 2026-07-27, rode: S22-S26, S28-S30, clears-when: the Agent tool reaches a local endpoint)
- liminal is the peer Claude session (local-LLM / fine-tuning expert), co-located on this host (3900x) at `~/chungus/dev/liminal`; it serves + scores local models on the shared RTX 3090 (SHARED with liminal's curator cron at :13 every 6h — during its training windows it evicts resident models, so gate heavy local calls on `nvidia-smi --query-gpu=memory.free` and keep pilot models warm via keep-alive). Locate its pane by NAME (windows renumber between sessions): `tmux list-panes -a -F '#{window_name} #{pane_id}' | awk '$1=="liminal"{print $2}'` (S28: pane `%10`). **Walkie-talkie send/verify/metachar-escape/return-path mechanics are canonical in `reference.md#cross-session-coordination` (dev bindings, dev.md § Worktrees & concurrent sessions points at it) — follow that, do NOT restate it here.** Boundary settled S28: liminal owns model selection and measurement, this repo owns the plugin/contracts/floors; liminal has standing write permission for `dev/experiments/model-tier/results-liminal-S{N}-*.md` and their in-flight `live-diffs/*` is theirs — never stage it. Any other cross-repo write needs a halt-ping and an explicit go-ahead first, both directions. (as-of: 2026-07-27, rode: S22-S26, S28-S30, clears-when: liminal stops running the local ladder)
- **Model-tier numbers are not comparable across two boundaries.** (1) The 0.77.0 prompt-source cut: pre-0.77.0 runs scored a drifted hand copy of the agent prompt, so never compare a pre- to a post-0.77.0 run (relative order within one pre-0.77.0 ladder is probably intact). (2) The extraction menu shape: `extraction-benchmark.md`'s gold set is still `bare` while the harness default is now `title`, so its scores are a starvation floor. Both caveats are stated in `dev/experiments/model-tier/README.md` and the benchmark file itself. (as-of: 2026-07-27, rode: S28-S30, clears-when: #139's gold set is re-derived under MENU_SHAPE=title and the pre-0.77.0 ladder is re-run)

## Open thread
None, closed clean. (S30, mbp, 2026-08-05) Release 0.78.5 shipped and all four requested reliability issues are closed.

## Next priority
| Source | Action | Effort | Why now | Blocked by |
|---|---|---|---|---|
| #140 | Add machine-readable graded-run log | Size-M · one session | Unblocks honest model planning | — |
| #139 | Rebuild extraction gold set | Size-M · one campaign | Current scores are a floor | #140 |
| #148 | Persist structural audit findings | Size-M · one session | Findings currently vanish | — |
| #149 | Surface source disagreements | Size-L · design first | Truth conflict is invisible | design decision |

**Cross-repo follow-ups:** liminal owes the primary-vs-contributory split by model size; `library-stack` owns the verifier-confirmed article overstatements.
