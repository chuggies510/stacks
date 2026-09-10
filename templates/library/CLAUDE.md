# Library

A source-grounded knowledge library managed with the Stacks Hermes release.

## Session start

Enumerate stacks, then choose one next action:

- No stacks: use `stacks:new-stack {name}`.
- Sources ready: place them in `{stack}/sources/incoming/`.
- Incoming sources: use a compatible Stacks harness to catalog them.
- Existing articles: use `stacks:lookup` to query grounded content.

## Conventions

- Sources in `sources/incoming/` are gitignored staging. They do not sync across machines.
- A compatible Stacks harness catalogs approved staged sources into tracked articles.
- `index.md` is the routing map used by `stacks:lookup`.
- `log.md` is append-only. Edit `STACK.md` to change the stack schema.
