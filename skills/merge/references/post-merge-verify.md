# Post-merge Verification Gate — Step 5's dispatch

Step 5 runs `lib/post-merge-verify-dispatch.sh` **after** the merge report has
printed. Five positionals, all already in hand from Steps 1-2, so nothing here
re-queries GitHub:

| # | Value | Source |
|---|-------|--------|
| 1 | PR number | Step 1's `<pr-number>` |
| 2 | `owner/repo` | Step 1's single remote URL, and the registry key |
| 3 | head ref | Step 2's `gh pr view` read `headRefName` |
| 4 | base ref | ditto `baseRefName` — never a hardcoded `main` |
| 5 | remote | the `[remote]` positional, default `origin` |

## Finding the wrapper (plugin-root tiers)

The wrapper ships **inside this plugin**, so Step 5 has to resolve the plugin
root before it can run anything. A block pasted into a shell has no self-path,
so it gets tiers 2 and 5 and nothing else — the ladder and the reasoning are
in
[`harness-skills` `references/plugin-root.md`](https://github.com/dEitY719/harness-skills/blob/main/references/plugin-root.md).

| Tier | What |
|---|---|
| 2 | `$CLAUDE_PLUGIN_ROOT`, guarded non-empty, **then proved** with `[ -f <root>/lib/post-merge-verify-dispatch.sh ]` |
| 5 | stop — `[FAIL]` for a registered repo, silence for an unregistered one |

`CLAUDE_PLUGIN_ROOT` is a **contract, not a Claude Code feature**. Claude Code
fills it; on Codex, Gemini CLI, Antigravity, Kimi, Hermes and OpenCode the
agent exports it itself, to the directory it read `SKILL.md` from. That is what
makes this gate reachable off Claude Code (#37) — there is no sixth fallback,
and `GH_VERIFY_ROOT` is not one: it points at a `gh-verify` checkout, while the
wrapper is a file of *this* plugin.

The `[ -f ]` is not decoration. Without it a plugin root that does not hold the
wrapper ran `sh <missing path>`, which prints a shell-level `No such file` and
never reaches the `[FAIL]` — the registered-repo gate silently skipped, which
is precisely the outcome the row below forbids. `tests/pmv-dispatch-resolves.sh`
cases 6c/6d cover both directions.

## The registry gate

The script is a **no-op for any repo missing** from
`${IW_WATCHED_REPOS:-${HOME}/.agent-factory/avatars/issue-watcher/watched-repos.json}`
— the untracked registry `issue_watcher_cron.sh` also reads (dEitY719/dotfiles#1555).
No registry, no `jq`, or an unlisted repo: no output, no dispatch, and no
`[WARN]` either. That path is byte-identical to how merges behaved before
dEitY719/dotfiles#1511.

## Failure modes (all soft — the report above always stands)

| Condition | Behaviour |
|---|---|
| Any of the five arguments blank, whitespace-only, or an unsubstituted `<placeholder>` | one `[WARN]` naming every offender, no dispatch (dEitY719/dotfiles#1576) |
| Repo not in the registry | silence |
| Repo registered, dispatch will not stage or will not source | one `[FAIL]` — a broken install, not an opt-out |
| Anything inside the dispatch | the dispatch's own `[WARN]`/`[INFO]` lines |

The script always exits 0. The merge already succeeded; nothing here may
change that outcome or suppress the report.

## Why a script and not `Skill(gh-verify:post-merge-verify, ...)`

The dispatch block is READ from its SSOT and sourced rather than reached
through a nested `Skill()` call: as a `Skill()` call this step ran 0/10 inside
`gh-pr:merge-train` vs 10/10 for every pasted block, and an unclosed tab
starves issue-watcher's budget (dEitY719/dotfiles#1565). The staging itself —
five-input validation, one registry lookup, first-`bash`-fence extraction,
source, cleanup — is a deterministic procedure, so it lives in a testable
script instead of a paste-this-verbatim markdown fence; getting the bindings
wrong by hand has already shipped twice (dEitY719/dotfiles#1565 silent
no-dispatch, dEitY719/dotfiles#1576 half-bound run).

The SSOT block resolves in two tiers — `GH_VERIFY_ROOT`'s live `gh-verify`
checkout, else `lib/vendor/gh-verify/post-merge-verify/dispatch.sh.md`. There
is deliberately no cwd tier: `gh-pr:merge` runs inside the PR checkout under
review, so a pull request could plant its own copy (harness-skills#22).
`tests/pmv-dispatch-resolves.sh` guards both halves.

The dispatch owns every step and every failure mode from there, and re-runs the
same registry gate on its own so it stays usable standalone
(`/gh-verify:post-merge-verify <N>`). Detail: the `gh-verify-skills` sibling
repo (`skills/post-merge-verify/SKILL.md`).
