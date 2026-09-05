# gh-pr:reply — Resolving the Target PR and Repo (Step 1)

Positional args: `<pr-number> [remote]` (`remote` defaults to `origin`).
Full argument table: `references/help.md`.

## PR number precedence

Runs **after** the target binding below, so the host is already pinned.

1. **Explicit arg** — `/gh-pr:reply 123` → PR #123.
2. **Current branch** — `GH_HOST="$TARGET_HOST" gh pr view --json
   number,url,headRefName,baseRefName`; stop if the branch has no PR. `--repo`
   is deliberately omitted **here only**: `gh` requires an explicit PR argument
   whenever `--repo` is set, which would defeat the branch detection. The
   `GH_HOST=` prefix still pins the server, and `gh` then infers the repo from
   the current checkout's remotes on that host.
3. Never guess, and never pick "the latest PR".

## TARGET_REPO + TARGET_HOST

Resolve both from the `[remote]` positional — one and the same remote URL — not
from `gh`'s default-repo heuristic, so a repo with two remotes on the same host
(e.g. `origin` + `upstream`) replies to the intended one. Bind `remote` to the
positional (default `origin`), source the SSOT helpers, and parse the remote's
URL (network-free):

```sh
# DOTFILES_FORCE_INIT=1 is load-bearing: the file's interactive guard
# otherwise returns early in a non-interactive shell and the helper is
# never defined. `remote` is the [remote] positional; ${remote:-origin}
# keeps the block self-contained whether or not it was set.
export DOTFILES_FORCE_INIT=1
_SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"
[ -f "$_SC/functions/gh_pr_review.sh" ] || _SC="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common"
[ -f "$_SC/functions/gh_pr_review.sh" ] || {
    printf '[gh-pr:reply] shell-common not found under %s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    return 1 2>/dev/null || exit 1
}
export SHELL_COMMON="$_SC"
. "$_SC/functions/gh_pr_review.sh"
_SC="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common"
[ -f "$_SC/functions/gh_host.sh" ] || _SC="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common"
[ -f "$_SC/functions/gh_host.sh" ] || {
    printf '[gh-pr:reply] shell-common not found under %s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    return 1 2>/dev/null || exit 1
}
export SHELL_COMMON="$_SC"
. "$_SC/functions/gh_host.sh"
REMOTE_URL=$(git remote get-url "${remote:-origin}") || {
  echo "Cannot resolve remote '${remote:-origin}' to a repo" >&2; exit 1; }
TARGET_REPO=$(_gh_pr_review_resolve_target_repo "${remote:-origin}") || {
  echo "Cannot resolve remote '${remote:-origin}' to a repo" >&2; exit 1; }
TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)
export GH_HOST="$TARGET_HOST"
export TARGET_REPO TARGET_HOST
```

`_gh_pr_review_resolve_target_repo` yields the **repo slug only** — it carries
no host, so the `TARGET_HOST` half above is what actually pins the server.

## Host targeting rule (issues dEitY719/dotfiles#1403, dEitY719/dotfiles#1407)

Every `gh` call this skill runs must name both host and repo:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

For `gh api` there is no `--repo` flag — the repo goes in the path
(`repos/$TARGET_REPO/...`) and the `GH_HOST=` prefix stays.

A `gh` call without `--repo` follows gh CLI's own `gh repo set-default`, not
git's remote; and `--repo <owner>/<repo>` carries no host, so on a dual-host
login (github.com + GHES) the slug resolves against the wrong server **without
an error** — that is the silent misroute dEitY719/dotfiles#1403 hit. `export GH_HOST` also lets
the helpers this skill sources (`gh_pr_review.sh`, `gh_pr_edit_safe.sh`,
`gh_project_status.sh`) inherit the same host; the reference files still spell
the prefix out on every example for copy-paste safety.

## Default-remote tradeoff

`[remote]` defaults to `origin`. This is more predictable than the old
`gh repo view` default-repo heuristic, but note the fork workflow where `origin`
is your fork and `upstream` is the canonical repo: there, reply explicitly with
`/gh-pr:reply <N> upstream`. On the `gh-verify:review-all` / `gh-flow:issue` path
the remote is threaded through, so the default only applies to a bare manual
`/gh-pr:reply <N>`.
