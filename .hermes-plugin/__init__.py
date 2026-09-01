"""Hermes Agent registration for the `gh-pr` skills plugin.

Registers the eight commit-to-merge skills with Hermes' native skill
loader so `skill_view("gh-pr:<name>")` can load them on demand.

Unlike superpowers, this plugin injects no session bootstrap context. These
skills are always invoked explicitly against a named PR or a working tree the
user just changed, and every one of the eight mutates something -- a commit, a
comment, a review verdict, a merge. Paying for a bootstrap preamble on every
first turn would buy nothing and nudge a model toward writes it was not asked
for.
"""

import os
from pathlib import Path

# Sentinel skill used to recognise a correctly laid out skills/ tree.
_SENTINEL = ("create", "SKILL.md")


def _skills_dir() -> str:
    """Locate the stock skills/ tree for either supported install layout.

    - git-clone install (`hermes plugins install dEitY719/gh-pr-skills`):
      the plugin dir is the repo root, so `.hermes-plugin/` and `skills/` are
      siblings and this module resolves `../skills`.
    - flattened install (plugin files copied to the plugin dir root): `skills/`
      sits next to this module.

    Raises loudly when neither matches -- a bootstrap that silently skips is how
    a broken install masquerades as a working one.
    """
    here = os.path.dirname(os.path.realpath(__file__))
    candidates = (
        os.path.realpath(os.path.join(here, "..", "skills")),
        os.path.realpath(os.path.join(here, "skills")),
    )
    for cand in candidates:
        if os.path.isfile(os.path.join(cand, *_SENTINEL)):
            return cand
    raise RuntimeError(
        "gh-pr plugin: cannot find the skills/ tree "
        f"(looked at {candidates}). Reinstall with "
        "`hermes plugins install dEitY719/gh-pr-skills`."
    )


def register(ctx):
    skills_dir = _skills_dir()

    # Register every stock skill with Hermes' native loader so skill_view can
    # load them on demand. Standard markdown; no conversion (plugin guide).
    # register_skill requires a pathlib.Path -- a str raises AttributeError and
    # hermes silently disables the whole plugin.
    for name in sorted(os.listdir(skills_dir)):
        skill_md = os.path.join(skills_dir, name, "SKILL.md")
        if os.path.isfile(skill_md):
            ctx.register_skill(name, Path(skill_md))
