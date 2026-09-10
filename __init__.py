"""Native Hermes adapter for stacks.

A registration and nothing else. The skills live where they already live, in
``skills/*/SKILL.md``, and this file points Hermes at those exact files so one body
serves every harness. It copies no prose, orchestrates nothing, and registers no hooks.

The safe Hermes release contains only the executable Stacks core. Install its
immutable release commit, then run ``hermes plugins enable stacks``. A top-level
``plugin.yaml`` keys on its ``name``, so the install directory, the registry id and the
skill namespace are all ``stacks``.

Hermes serves a plugin skill by QUALIFIED name only (``stacks:lookup``). Plugin
registrations are deliberately kept out of ``~/.hermes/skills/`` and out of
``<available_skills>`` (hermes_cli/plugins.py::PluginContext.register_skill), so a bare
name will not resolve and this adapter does not pretend otherwise. Qualified skills DO
appear in ``skills_list()``, whose descriptions come from registration metadata, which is
why each one is passed through below.

What this does NOT provide, stated rather than degraded into silence:

- The worker-based `catalog-sources`, `audit-stack`, and `enrich-stack` workflows
  are not included in this release. `lookup`, `new-stack`, `process-inbox`, and
  `init-library` dispatch no workers.
- ``ingest-book`` additionally depends on the separate ``doc-tools`` package.
"""

from __future__ import annotations

import os
from pathlib import Path

PLUGIN_NAME = "stacks"

# Every executable skill fence resolves ``STACKS_ROOT`` itself, preferring
# ``$STACKS_PLUGIN_ROOT`` ahead of the Claude, Pi and Codex arms (39 projections, pinned
# by tests/plugin-root.bats). Publishing the real root into that existing seam is what
# makes the fences work under Hermes, which none of the other arms can resolve. First
# preference is the only correct position: a trailing Hermes arm would lose to a stale
# ``~/.claude/settings.json`` entry and silently run a different checkout.
#
# Hermes's local backend builds each child's environment from ``os.environ`` at call time
# (tools/environments/local.py::_make_run_env) and strips only credential-shaped names, so
# a value set here is what a skill's Bash fence reads. Proved end to end, through that same
# function, in tests/hermes-native.bats.
ROOT_ENV_VAR = "STACKS_PLUGIN_ROOT"


def source_root() -> Path:
    """The directory this adapter lives in, which is the package root Hermes imported."""
    return Path(os.path.realpath(__file__)).parent


def skill_description(skill_md: Path) -> str:
    """The ``description:`` from a SKILL.md's frontmatter, or "" when absent.

    Line-oriented on purpose, bounded by the CLOSING ``---``: a scan that runs past it
    walks into the body and returns body prose as a description. First occurrence wins.
    """
    lines = skill_md.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return ""
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if line.startswith("description:"):
            return line.partition(":")[2].strip().strip("\"'")
    return ""


def _skill_files(root: Path) -> list[Path]:
    """Every ``skills/*/SKILL.md`` under *root*, or raise.

    An empty result raises rather than registering nothing, because a plugin that loads
    and provides zero skills reads exactly like a working install. Asking whether
    ``skills/`` exists would not catch that: an empty directory passes that check.
    """
    found = sorted(root.glob("skills/*/SKILL.md"))
    if not found:
        raise RuntimeError(
            f"{PLUGIN_NAME} Hermes adapter: no skills/*/SKILL.md under {root}. "
            "Reinstall the pinned Stacks Hermes release.")
    return found


def register(ctx) -> None:
    root = source_root()
    skills = _skill_files(root)
    # Set unconditionally. This names a CODE ROOT, not an identity label: a value
    # inherited from whatever launched this process would point a Hermes session at a
    # different checkout than the one it registered skills from, and run that instead.
    # ponytail: process-global, so a single process multiplexing two profiles with
    # DIFFERENT stacks checkouts gets last-writer-wins. Per-profile scoping only if that
    # ever becomes real; one install per profile home is the normal case.
    os.environ[ROOT_ENV_VAR] = str(root)
    for skill_md in skills:
        description = skill_description(skill_md)
        if not description:
            # A silently description-less skill is unroutable in skills_list().
            raise RuntimeError(
                f"{PLUGIN_NAME} Hermes adapter: {skill_md} has no frontmatter description.")
        ctx.register_skill(skill_md.parent.name, skill_md, description=description)
