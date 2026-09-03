# gh-pr:create — Positional Args and GitHub Target (#1403, #1405)

Run this in Step 1a-0, **before any `gh` call**.

## Positional args (#1405)

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

```bash
REMOTE="${REMOTE:-origin}"
_SC="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common"
[ -f "$_SC/functions/gh_host.sh" ] || { _SC="${CLAUDE_PLUGIN_ROOT:-}/lib/vendor/shell-common"; export SHELL_COMMON="$_SC"; }
. "$_SC/functions/gh_host.sh"
REMOTE_URL=$(git remote get-url "$REMOTE")
GH_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL")
TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)
export GH_HOST="$TARGET_HOST"
export GH_REPO TARGET_HOST REMOTE
```

Every `gh` call in this skill — `gh repo view`, `gh pr list`, `gh pr view`,
`gh pr create`, `gh label list` — then runs as
`GH_HOST="$TARGET_HOST" gh ... --repo "$GH_REPO"`.

## Why

A bare `gh` follows gh CLI's own `gh repo set-default` instead of git's
`$REMOTE`, so on a dual-host login (github.com + GHES) it silently targets the
wrong server: the base branch comes from the wrong repo, or the PR is opened
against it.
