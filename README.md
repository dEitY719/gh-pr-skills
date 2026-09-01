# gh-pr-skills

Eight skills for the GitHub **commit-to-merge lifecycle** — everything that
happens once a branch has something on it. Commit it, open the PR, get a
second-opinion review from an external AI CLI, answer every review comment,
approve, merge. Plus the two skills for when the straight line does not hold: an
audited emergency override and a serial merge train. Packaged as a single plugin
named `gh-pr`, installable on six coding-agent harnesses.

Its siblings own the rest of the pipeline:
[`gh-issue-skills`](https://github.com/dEitY719/gh-issue-skills) (issue and
discussion lifecycle) and
[`gh-flow-skills`](https://github.com/dEitY719/gh-flow-skills) (one-shot
compositions that chain both). Like
[`gh-issue-skills`](https://github.com/dEitY719/gh-issue-skills), this repo owns
no shared assets — it links out for the
[per-harness tool mappings and the CI workflow](#shared-assets).

## Skills

| Skill | Invoke | What it does |
|-------|--------|--------------|
| `commit` | `/gh-pr:commit [issue] [remote]` | Creates one commit in the repo's own style, auto-linking a GitHub issue number. **Commits only** — never pushes, never opens a PR. |
| `create` | `/gh-pr:create [issue] [remote]` | Opens the PR from **every commit since the branch diverged from base**, not just HEAD. Ensures the `Closes #N` footer. No review, no merge. |
| `review` | `/gh-pr:review <PR#> --ai <cli> [remote]` | Delegates a second-opinion review to one external AI CLI (`codex`/`agy`/`claude`/`opencode`/`hermes`) and posts one aggregate comment. **Submits no verdict.** |
| `reply` | `/gh-pr:reply <PR#> [remote]` | Replies to **every** review comment individually, bots included, and applies the fixes that hold up. Not a summary comment. |
| `approve` | `/gh-pr:approve <PR#> [remote]` | The only skill that submits a verdict. Blockers become `request changes`; everything else becomes a follow-up issue. A self-authored PR can never be approved — `--self-record` and `--admin-merge` are the audited alternatives. |
| `merge` | `/gh-pr:merge <PR#> [strategy] [remote]` | Rebase by default, or squash/merge. Refuses un-approved PRs, failing CI, drafts, and conflicts. Always `--delete-branch`. |
| `merge-emergency` | `/gh-pr:merge-emergency <PR#> "<reason>"` | Admin-overrides the approval gate, forcing an audit trail: a reason comment plus a follow-up incident issue. **CI still gates.** |
| `merge-train` | `/gh-pr:merge-train [repo] [remote]` | Walks your own open PRs one at a time, routing each to `gh-resolve:outdated` / `:conflict` / `:ci-fail` before handing it to `merge`. |

`review` and `approve` are a pair split by *authority*: `review` gathers an
outside opinion and can only comment, `approve` is the one place a verdict is
submitted. `reply` sits between them and is where the fixes actually land.

`merge` and `merge-emergency` are the same split applied to merging: the first
refuses, the second overrides — and pays for the override in writing.

Unlike `gh-issue-skills`, there is **no read-only skill here**. All eight write
to a live repo.

## Requirements

| Skill | Needs |
|-------|-------|
| `commit` | `git` and a repo with staged or unstaged changes. Metrics and board sync additionally need `gh` with write access. |
| `create` | `gh` with write access to PRs, plus a feature branch with an upstream it can push to. |
| `review` | The external AI CLI named by its required `--ai` flag, on `PATH` (`codex`, `agy`, `claude`, `opencode`, `hermes`). It delegates the reading; it does not review the diff itself. |
| `reply` | `gh` with write access to PR review comments, and a working tree it can edit for the fixes. |
| `approve` | `gh` with permission to submit reviews on the target repo. Cannot act on a PR authored by the same user. |
| `merge`, `merge-emergency` | `gh` with merge permission. `merge-emergency` additionally needs admin rights to bypass branch protection, and files an incident issue. |
| `merge-train` | Everything `merge` needs, plus the `gh-resolve` plugin for the per-PR remediation routes. |

Every skill carries `GH_HOST` **and** `--repo` on every `gh` call, both resolved
from the same remote URL. `--repo` alone names no server: on a dual-host login
(github.com plus a GHES instance) a bare call silently queries the wrong one
(dotfiles #1403 / #1407).

## Install

### Claude Code

```
/plugin marketplace add dEitY719/gh-pr-skills
/plugin install gh-pr@gh-pr-skills
```

### Codex

```
codex plugin install dEitY719/gh-pr-skills
```

### Kimi CLI

```
kimi plugin install dEitY719/gh-pr-skills
```

### Hermes Agent

```
hermes plugins install dEitY719/gh-pr-skills
```

### OpenCode

See [`.opencode/INSTALL.md`](.opencode/INSTALL.md).

### Gemini CLI / Antigravity

```
gemini extensions install https://github.com/dEitY719/gh-pr-skills
```

Antigravity (`agy`) shares `~/.gemini`, so it inherits the install.

## Harness support

These are `gh` CLI calls, `git` calls, and file writes, so they port cleanly
with two exceptions — `merge-train` chains the other skills through Claude
Code's `Skill()` tool, and `approve` / `review` hand a large diff to a subagent.
Every gap and its workaround is documented per harness in
[`harness-skills/references/`](https://github.com/dEitY719/harness-skills/tree/main/references);
read the one file for the harness you are on.

| Skill | Claude Code | Codex | Kimi | Gemini / Antigravity | Hermes | OpenCode |
|-------|:-----------:|:-----:|:----:|:--------------------:|:------:|:--------:|
| `commit` | full | full | full | full | full | full |
| `create` | full | full | full | full | full | full |
| `review` | full | inline diff | full | inline diff | inline diff | inline diff |
| `reply` | full | full | full | full | full | full |
| `approve` | full | inline diff | full | inline diff | inline diff | inline diff |
| `merge` | full | full | full | full | full | full |
| `merge-emergency` | full | full | full | full | full | full |
| `merge-train` | full | manual chain | manual chain | manual chain | manual chain | manual chain |

*inline diff* — `approve` and `review` dispatch a large diff to a subagent on
Claude Code and Kimi (`Agent`). Elsewhere they read it inline. Same verdict,
more tokens in one context.

*manual chain* — `merge-train`'s loop calls the per-PR skills through `Skill()`.
Without a skill-invocation tool, run them yourself, one PR at a time:
`gh-resolve:outdated` / `:conflict` / `:ci-fail`, then `gh-pr:merge`. The gates
are per-PR, so nothing is skipped by driving them by hand — only the walking is.

## Shared assets

This repo owns none — deliberately.

- **Per-harness tool mappings** live in
  [`harness-skills/references/`](https://github.com/dEitY719/harness-skills/tree/main/references)
  (`{codex,kimi,gemini,antigravity,hermes,opencode}-tools.md`). That repo is
  their sole owner; the other fourteen `*-skills` repos link there rather than
  carrying copies, so one tool rename is one edit, not fifteen
  (dotfiles #1410 F-5 / NF-2). The only condensed mirror here is
  `.kimi-plugin/plugin.json`'s `skillInstructions`, because Kimi CLI cannot read
  a reference file at load time — it points back to the canonical file.
- **The reusable CI workflow** is
  [`harness-skills/.github/workflows/skill-check.yml`](https://github.com/dEitY719/harness-skills/blob/main/.github/workflows/skill-check.yml)
  (#1410 D-10). See [CI](#ci).

## Layout

Manifests live at the repo root and all point at one flat `skills/` directory:

```
.
├── skills/{commit,create,review,reply,approve,merge,merge-emergency,merge-train}/
│   ├── SKILL.md
│   └── references/
├── .claude-plugin/{marketplace,plugin}.json     Claude Code
├── .codex-plugin/plugin.json                    Codex
├── .kimi-plugin/plugin.json                     Kimi CLI
├── .hermes-plugin/{plugin.yaml,__init__.py}     Hermes Agent
├── .opencode/plugins/gh-pr.js + INSTALL.md      OpenCode
├── .agents/plugins/marketplace.json             Antigravity
├── gemini-extension.json + GEMINI.md            Gemini CLI
├── package.json
├── CLAUDE.md · AGENTS.md -> CLAUDE.md
└── LICENSE
```

Only Claude Code understands a nested `plugins/<name>/skills/` layout. The other
five harnesses resolve manifests at the repo root and a skills tree at
`./skills/`, so this repo keeps everything flat. See [`CLAUDE.md`](CLAUDE.md) for
the full rationale and contribution rules.

Skill directory names dropped their old `gh-pr-` / `gh-` prefixes in the
migration: `/gh-pr:gh-pr-merge` stutters, and the plugin namespace already
carries the meaning the prefix used to (#1410 F-4).

One name needed a judgement call. `gh:pr` was the only skill whose directory
name was *identical* to the plugin name, so stripping the redundant prefix would
have left nothing. It became `create` — the verb for what it actually does, and
a deliberate mirror of `gh-issue:create`, so the same word means "file the
thing" in both plugins (#1677 §3).

The `.kimi-plugin/` manifest is pre-provisioned: Kimi CLI is not installed on the
maintainer's machines yet, and shipping the manifest now costs nothing and saves
a migration later.

## Cross-repo names

Like `gh-issue-skills` and unlike the Phase 2 repos, this one was migrated
**after** the Phase 3 names were fixed, so every reference to a sibling repo is
written in its final form (#1677 §2):

| Old | New | Lives in |
|-----|-----|----------|
| `gh:commit` | `gh-pr:commit` | this repo |
| `gh:pr` | `gh-pr:create` | this repo |
| `gh:pr-review` / `-reply` / `-approve` | `gh-pr:review` / `:reply` / `:approve` | this repo |
| `gh:pr-merge` / `-merge-emergency` / `-merge-train` | `gh-pr:merge` / `:merge-emergency` / `:merge-train` | this repo |
| `devx:pr-review-all` | `gh-verify:review-all` | `gh-verify-skills` |
| `gh:pr-post-merge-verify` | `gh-verify:post-merge-verify` | `gh-verify-skills` |
| `gh:pr-resolve-ci-fail` / `-conflict` / `-outdated` | `gh-resolve:ci-fail` / `:conflict` / `:outdated` | `gh-resolve-skills` |
| `gh:label-bootstrap` | `gh-setup:label-bootstrap` | `gh-setup-skills` |
| `gh:issue-create` | `gh-issue:create` | `gh-issue-skills` |
| `gh:issue-flow` | `gh-flow:issue` | `gh-flow-skills` |
| `ai-worktree:teardown` | `session:worktree-teardown` | `session-skills` |

The last two rows are references to repos that did not exist when this migration
ran. Writing them in final form now is cheaper than a second pass later, and
`gh-flow-skills` reads `gh-pr:create` / `gh-pr:commit` straight out of this
repo's decision.

Unlike `gh-issue-skills`, the step-marker wire format **did** move here. `create`
prints `[step:gh-pr-create/<id>] OK` and `commit` prints
`[step:gh-pr-commit/<id>] OK`; dotfiles #1677 F-8 added matching
`skill_step_catalog.yml` keys alongside the old `gh-pr` / `gh-commit` ones,
which stay to guard the un-deleted dotfiles originals until Phase 4. The step
IDs inside the markers are unchanged.

## CI

[`.github/workflows/validate.yml`](.github/workflows/validate.yml) calls the
reusable workflow owned by `harness-skills`:

```yaml
jobs:
  validate:
    uses: dEitY719/harness-skills/.github/workflows/skill-check.yml@main
    with:
      plugin-name: gh-pr
      max-skill-lines: 197
      allow-emoji-paths: |
        skills/approve/references/ai-metrics.md
        ...
```

It validates manifests, skill frontmatter (the `name:` must be bare and match
the directory), progressive-disclosure line limits, the Codex description budget,
version agreement across all seven manifests, shell scripts, and the no-emoji
rule. There is no local copy to keep in sync; a check added upstream applies here
on the next run.

`max-skill-lines` is pinned above the 100-line default because four `SKILL.md`
files arrived from dotfiles already over it (`merge` 197, `merge-train` 146,
`reply` 143, `review` 110). That is tracked migration debt, not a new standard —
see [`CLAUDE.md`](CLAUDE.md) → "Known migration debt".

The `allow-emoji-paths` entries cover text the skills **quote** rather than
decorate with: the ai-metrics footer, whose chart / person / robot glyphs are the
wire format itself (dotfiles #317 F-2, PR #320). Nothing else in the repo may
carry an emoji.

## Provenance

These skills were extracted from
[`dEitY719/dotfiles`](https://github.com/dEitY719/dotfiles)
(`claude/skills/{gh-commit,gh-pr,gh-pr-review,gh-pr-reply,gh-pr-approve,gh-pr-merge,gh-pr-merge-emergency,gh-pr-merge-train}`)
as a content snapshot — no history rewriting. The dotfiles copies remain in
place; they are removed in Phase 4 of that repo's migration (#1410 NF-1 / NF-3).
Behaviour is unchanged from the snapshot; only the namespace moved, from `gh:` to
`gh-pr:`, and the directory names lost their now-redundant prefixes.

Because behaviour was held fixed, some coupling to the dotfiles checkout came
across with it — several skills source `shell-common/functions/*.sh`, and
`merge` reads a dispatch block from a dotfiles path. Both are enumerated in
[`CLAUDE.md`](CLAUDE.md) → "Known migration debt" and are Phase 4 work.

This is Phase 3 of the dotfiles #1410 migration, shared with `gh-issue-skills`
and `gh-flow-skills`. `packaging-skills` was Phase 0, and `harness-skills` was
Phase 1 and is the sibling that owns the shared assets this repo links to.

## License

MIT. See [LICENSE](LICENSE).
