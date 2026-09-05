# Argument parsing — flags, rejections, GitHub target, fetch list

## Positional + flags

Positional: `<pr-number>` and `<remote>` (default `origin`). Flags may
appear anywhere:

- `--self-record` - self-authored PR only; submit a comment-only record.
- `--admin-merge` - self-authored PR only; after a blocker-free review,
  run `gh pr merge --admin`.
- `--squash`, `--rebase`, `--merge` - optional strategy for
  `--admin-merge`; reject if used without it.

## Rejections

Reject unknown flags, `--self-record` with `--admin-merge`, and legacy
`--self-ok` with:
`--self-ok is not supported; GitHub blocks self-approval server-side.`

## GitHub target (dEitY719/dotfiles#1403/dEitY719/dotfiles#1407)

Bind host and repo from **one and the same** remote URL, before any `gh` call:

```bash
_SC="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common"
[ -f "$_SC/functions/gh_host.sh" ] || _SC="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common"
[ -f "$_SC/functions/gh_host.sh" ] || {
    printf '[gh-pr:approve] shell-common not found under %s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    return 1 2>/dev/null || exit 1
}
export SHELL_COMMON="$_SC"
. "$_SC/functions/gh_host.sh"
REMOTE_URL=$(git remote get-url "${REMOTE:-origin}") || exit 1
TARGET_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL") || exit 1
TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)
export GH_HOST="$TARGET_HOST"
export TARGET_REPO TARGET_HOST
```

Every `gh` call in this skill then runs as
`GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"`.

`--repo` alone is not enough: an `<owner>/<repo>` slug carries no host, so `gh`
resolves it against its own `gh repo set-default` instead of git's remote. On a
dual-host login (github.com + GHES) that silently reads — or writes — to the
wrong server with no error. `GH_HOST=` pins the server, `--repo` pins the repo;
neither substitutes for the other. The `export` also passes the host down to the
helpers this skill sources (`gh_project_status.sh`).

Missing remote: list `git remote -v` and stop — never fall back to `origin`
silently. If `_gh_host_from_url` fails (non-GitHub remote), fall back to
`_gh_resolve_host`; never proceed with an empty `TARGET_HOST`.

## Parallel fetch (before reading the diff)

- `TARGET_HOST` / `TARGET_REPO` per the section above.
- PR number: explicit arg or `GH_HOST="$TARGET_HOST" gh pr view --json
  number` on current branch; if neither exists, stop and ask. `--repo` is
  deliberately omitted **on this one call**: `gh` requires an explicit PR
  argument whenever `--repo` is set (`argument required when using the
  --repo flag`), which would defeat the branch detection. The `GH_HOST=`
  prefix still pins the server, and `gh` then infers the repo from the
  current checkout's remotes on that host. Every other `gh pr view <N>`
  below has a positional and keeps `--repo`.
- `ME=$(GH_HOST="$TARGET_HOST" gh api user -q .login)` — not repo-scoped,
  host prefix only.
- PR JSON: `number,title,author,state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefName,baseRefName,files`
- `REBASEABLE=$(GH_HOST="$TARGET_HOST" gh api "repos/$TARGET_REPO/pulls/<N>" --jq .rebaseable)` —
  the `rebaseable` field is REST-only; `gh pr view --json rebaseable`
  fails with `Unknown JSON field` because GraphQL has no such field.
- Prior reviews/comments on this PR by `ME`.
- `GH_HOST="$TARGET_HOST" gh pr checks <N> --repo "$TARGET_REPO"`.

## Gate decisions

Stop on `state != OPEN`, draft, or required-check failure. Warn (but
do not stop) on `mergeable: CONFLICTING` or `rebaseable: false` —
prepend a visible conflict warning block to the review body and include
it in the Step 5 report.
If `author.login == ME`, follow `references/self-pr-handling.md`.
If prior `ME` comments/reviews exist, use re-review mode: every prior
concern must be verified as fixed, tracked, or acceptably declined.
