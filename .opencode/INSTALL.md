# Installing gh-pr for OpenCode

## Prerequisites

- [OpenCode.ai](https://opencode.ai) installed
- An authenticated `gh` CLI with write access to the repo you are working in
- `commit` and `create` additionally need a feature branch — both refuse to run
  on the default branch
- `review` needs at least one external AI CLI on `PATH` (`codex`, `agy`, …); it
  delegates the reading to that CLI rather than doing it itself

## Installation

Add the plugin to the `plugin` array in your `opencode.json` (global or
project-level):

```json
{
  "plugin": ["gh-pr-skills@git+https://github.com/dEitY719/gh-pr-skills.git"]
}
```

OpenCode installs the package and runs `.opencode/plugins/gh-pr.js`, which
appends this repo's `skills/` directory to `config.skills.paths`. No symlinks
and no further config edits are needed — the native `skill` tool discovers all
eight on the next session.

## Verify

```
skill gh-pr:create
```

should load `skills/create/SKILL.md`. If it does not, check that the plugin
entry resolved (OpenCode logs the plugin load) and that `skills/create/SKILL.md`
exists in the installed copy.

## Notes

- The plugin injects **no** per-session bootstrap context. These skills are
  invoked explicitly against a named PR; all eight write to a live repo, so
  keeping them out of the preamble is deliberate.
- `merge-train` chains the other skills through Claude Code's `Skill()` tool,
  which OpenCode has no equivalent for. Run the per-PR skills directly instead —
  `gh-resolve:outdated` / `:conflict` / `:ci-fail`, then `gh-pr:merge` — one PR
  at a time.
- `approve` and `review` delegate a large diff to a subagent on Claude Code.
  Without a subagent tool they read the diff inline; that is a slower route to
  the same verdict, not a reduced one.
- `merge-emergency` requires a written reason of at least 10 characters and
  files an incident issue. That is the audit trail — do not stub it out.
- Per-harness tool mappings live in the sibling repo
  [`harness-skills/references/`](https://github.com/dEitY719/harness-skills/tree/main/references)
  (`opencode-tools.md`). This repo keeps no copy.
