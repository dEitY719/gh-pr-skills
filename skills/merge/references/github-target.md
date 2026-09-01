# gh-pr:merge — GitHub Target Binding (#1403, #1407)

Run this in Step 1, **before any `gh` call**.

## Bind the target

`remote` is the third positional (default `origin`). Resolve the repo **and**
the host from one and the same remote URL, then export the host so the helpers
this skill sources (`gh_project_status.sh`, `gh_pr_edit_safe.sh`) inherit it:

```bash
. "${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_host.sh"
REMOTE_URL=$(git remote get-url "${REMOTE:-origin}") || exit 1
TARGET_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL") || exit 1
TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)
export GH_HOST="$TARGET_HOST"
export TARGET_REPO TARGET_HOST
```

An unknown remote stops the run with `git remote -v` — never a silent `origin`
fallback.

## Host targeting rule

Every `gh` call in this skill — `gh pr view`, `gh pr checks`, `gh pr merge`,
`gh api` — runs as:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

`gh api` has no `--repo` flag: the repo goes in the path
(`repos/$TARGET_REPO/...`) and the `GH_HOST=` prefix stays.

## Why

A bare `gh` follows gh CLI's own `gh repo set-default` instead of git's
`$REMOTE`, and `--repo <owner>/<repo>` carries no host at all. On a dual-host
login (github.com + GHES) the slug then resolves against the wrong server
**without an error** — the silent misroute #1403 hit. For this skill that
misroute lands on `gh pr merge --delete-branch`, the most destructive write in
the repo, so both halves are mandatory.
