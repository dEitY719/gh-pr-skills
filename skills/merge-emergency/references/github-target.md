# gh-pr:merge-emergency — GitHub Target Binding (#1403, #1407)

Run this in Step 1, **before any `gh` call**.

## Bind the target

`remote` is the third positional (default `origin`). Resolve the repo **and**
the host from one and the same remote URL, then export the host so the helpers
this skill sources (`gh_project_status.sh`) inherit it:

```bash
_SC="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common"
[ -f "$_SC/functions/gh_host.sh" ] || { _SC="${CLAUDE_PLUGIN_ROOT:-}/lib/vendor/shell-common"; export SHELL_COMMON="$_SC"; }
. "$_SC/functions/gh_host.sh"
REMOTE_URL=$(git remote get-url "${REMOTE:-origin}") || exit 1
TARGET_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL") || exit 1
TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)
export GH_HOST="$TARGET_HOST"
export TARGET_REPO TARGET_HOST
```

An unknown remote stops the run with `git remote -v` — never a silent `origin`
fallback.

## Host targeting rule

Every `gh` call in this skill — `gh pr checks`, `gh pr comment`, `gh pr merge`,
`gh pr view`, `gh label list`, `gh issue create` — runs as:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

Host-only sub-commands (`gh api user`, `gh api graphql`) take the `GH_HOST=`
prefix and no `--repo` — `gh api` has no such flag; a repo-scoped `gh api` puts
the repo in the path instead (`repos/$TARGET_REPO/...`).

## Exception — `gh pr <verb>` with no PR argument

`gh pr view` (and any `gh pr <verb>` taking `[<number> | <url> | <branch>]`)
refuses `--repo` unless a PR argument is given:

```
$ gh pr view --repo <owner>/<repo> --json number
argument required when using the --repo flag
```

So the Step 1 auto-detect — the deliberately number-less `gh pr view` that reads
the PR off the **current branch** — runs with the host prefix only:

```bash
GH_HOST="$TARGET_HOST" gh pr view --json number,...
```

That still pins the server; `gh` then infers the repo from the current
checkout's remotes on that host. Every other call in this skill passes an
explicit `<N>` and therefore keeps `--repo "$TARGET_REPO"`.

## Why

A bare `gh` follows gh CLI's own `gh repo set-default` instead of git's
`$REMOTE`, and `--repo <owner>/<repo>` carries no host at all. On a dual-host
login (github.com + GHES) the slug then resolves against the wrong server
**without an error** — the silent misroute #1403 hit.

This skill runs `gh pr merge --admin --squash --delete-branch`. A misrouted
admin merge is unrecoverable and its audit trail (comment + incident issue)
would be filed on the wrong server, so both halves are mandatory here.
