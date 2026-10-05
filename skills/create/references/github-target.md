# gh-pr:create — Positional Args and GitHub Target (dEitY719/dotfiles#1403, dEitY719/dotfiles#1405)

Run this in Step 1a-0, **before any `gh` call**.

## Positional args (dEitY719/dotfiles#1405)

`/gh-pr:create [N] [remote] [--no-stack] [--base <branch>]` — a positional made only
of digits is the issue number, any other positional is the remote name;
`$REMOTE` defaults to `origin`.

`$REMOTE` drives the GitHub API target below **and** every git plumbing call in
this skill (`git fetch "$REMOTE"`, `"$REMOTE/$BASE_BRANCH"` ranges, `git push
-u "$REMOTE" HEAD`). An unknown remote stops the run with `git remote -v` —
never a silent `origin` fallback (same Failure rule as
`gh-issue-implement/references/repo-resolution.md`).

## Bind the target

Resolve the host and the repo from one and the same remote URL, then export the
host so the sourced helpers (`gh_project_status.sh`, `gh_pr_edit_safe.sh`)
inherit it:

The binding lives in `lib/github-target.sh` (relative to `skills/create/`);
`SKILL.md` Step 1 holds the guarded call. Contract:

| | |
|---|---|
| Input | `[remote]` (default `origin`) |
| stdout | one `export SHELL_COMMON=… GH_HOST=… GH_REPO=… TARGET_HOST=… REMOTE=…` line, values single-quoted, for the caller to `eval` |
| Loader | HARD tier ladder: tier 1 `$DOTFILES_ROOT` (default `$HOME/dotfiles`), tier 2 guarded `$CLAUDE_PLUGIN_ROOT/lib/vendor`, no cwd tier, tier 5 stops |
| Exit | `0` bound; `1` no usable shell-common or unknown remote (`git remote -v` on stderr) — stdout stays empty, so nothing half-bound is ever eval'd |

`tests/create-lib.sh` is the offline guard.

Every `gh` call in this skill — `gh repo view`, `gh pr list`, `gh pr view`,
`gh pr create`, `gh label list` — then runs as
`GH_HOST="$TARGET_HOST" gh ... --repo "$GH_REPO"`.

## Why

A bare `gh` follows gh CLI's own `gh repo set-default` instead of git's
`$REMOTE`, so on a dual-host login (github.com + GHES) it silently targets the
wrong server: the base branch comes from the wrong repo, or the PR is opened
against it.
