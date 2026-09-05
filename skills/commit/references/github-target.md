# gh-pr:commit — Positional Args and GitHub Target (dEitY719/dotfiles#1403, dEitY719/dotfiles#1405)

Step 1 parses the positionals and resolves the host and repo from the chosen
remote's URL in the same message that inspects the working tree, then exports
them for Step 5.

## Positional args (dEitY719/dotfiles#1405)

`/gh-pr:commit [issue-number] [remote]` — a positional made only of digits is the
issue number, any other positional is the remote name. `/gh-pr:commit 123`,
`/gh-pr:commit upstream`, `/gh-pr:commit 123 upstream` all work; bare `/gh-pr:commit` is
unchanged. Remote defaults to `origin`.

## Bind the target

If `git remote get-url "$REMOTE"` fails, stop with the available-remotes list
(`git remote -v`) and `Error: remote '<name>' not found. Available remotes:` —
never fall back to `origin` silently, which masks typos and posts metrics to
the wrong repo (same Failure rule as
`gh-issue-implement/references/repo-resolution.md`).

```bash
REMOTE="${REMOTE:-origin}"
_SC="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common"
[ -f "$_SC/functions/gh_host.sh" ] || _SC="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common"
[ -f "$_SC/functions/gh_host.sh" ] || {
    printf '[gh-pr:commit] shell-common not found under %s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    return 1 2>/dev/null || exit 1
}
export SHELL_COMMON="$_SC"
. "$_SC/functions/gh_host.sh"
REMOTE_URL=$(git remote get-url "$REMOTE")
TARGET_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL")
TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)
export GH_HOST="$TARGET_HOST"
export TARGET_REPO TARGET_HOST REMOTE
```

Every `gh` call in Step 5 is then
`GH_HOST="$TARGET_HOST" gh ... --repo "$TARGET_REPO"`.

## Why

A bare `gh` follows gh CLI's own `gh repo set-default`, not git's `$REMOTE`; on
a dual-host login (github.com + GHES) that posts to the wrong server with no
error. `export` is what carries the host into `gh_project_status.sh`, which
calls `gh` on its own — and it is what makes `/gh-pr:commit <N> upstream` sync
`upstream`'s board rather than `origin`'s.
