# Step 4.5 — promote the PR card to `Approved`

`gh-pr:approve` is the **sole owner** of the `Approved` column (issue
dEitY719/dotfiles#1350). No other skill may promote a card into it. Run this block right
after the Step 4 review submission succeeds, and only on the paths that
represent a human deciding "this PR is reviewed and ready":

| Step 4 path | Promote? | Bypass needed? |
|---|---|---|
| 4a clean LGTM (`--approve`) | yes | no — `reviewDecision` is now `APPROVED` |
| 4b approve with follow-up issues (`--approve`) | yes | no — same |
| 4c request changes | **no** | — |
| self-PR, `--self-record` | yes | **yes** (`reviewDecision` stays empty forever) |
| self-PR, analysis-only (default) | **no** — no GitHub mutation at all | — |
| self-PR, `--admin-merge` | **no** — the merge itself drives the card to `Done` | — |

## Why `--self-record` needs the bypass

`shell-common/functions/gh_project_status.sh` fail-closes any
`_gh_project_status_sync pr <N> "Approved"` whose `reviewDecision` is not
`APPROVED` (dEitY719/dotfiles#393). GitHub refuses self-approval server-side, so a solo
repo's own PR is stuck at `reviewDecision == ""` no matter what. The
guard stays in place for every other caller; `--self-record` is the one
place where a human has explicitly said "I reviewed my own PR", so it
carries the single-call bypass.

## Why prefix form, not `env`

`_gh_project_status_sync` is a shell function. `env VAR=val funcname …`
would `exec env` and look for a binary named `_gh_project_status_sync`
on `$PATH` — that fails. The POSIX prefix form `VAR=val funcname …`
scopes the binding to that one invocation, so the main shell never sees
the bypass.

## Why `--only-from "Backlog,In progress,In review"`

Defense-in-depth: `Done` is deliberately absent, so a re-review on an
already-merged PR cannot resurrect a `Done` card into `Approved`. That
`Done` exclusion is the whole point of the filter.

The three allowed origins match
`.github/workflows/project-board-sync.yml`'s `pull_request_review.submitted`
handler exactly. Both writers promote on the same human signal, so they
must accept the same starting columns — otherwise the skill path refuses
a promotion the workflow path would have made.

A narrower `--only-from "In review"` was tried first and rejected: the
`Code changes requested` builtin drops a PR card to `In progress`, and
`In progress -> In review` recovery is only automatic when the author
runs `/gh-pr:reply` and it actually pushes fix commits (its Step 6.5).
On every other route back — a manual push, `/gh-resolve:ci-fail`, a
reply round where every comment was declined — the card stays at
`In progress` and `/gh-pr:approve` silently refuses to promote it. Before
dEitY719/dotfiles#1513, `gh-pr:merge` Step 2-B would then fail-close on `Status !=
Approved`, pushing a normally-reviewed PR onto the emergency merge path
for a bookkeeping reason — that specific consequence is gone now that
Step 2-B is retired, but the underlying point stands: requiring the
card to have *visibly* passed through `In review` before it can reach
`Approved` is not worth complicating this guard for; the human running
`/gh-pr:approve` is the review signal, regardless of which column the
card came from.

## The block (soft-fail — never blocks the Step 5 report)

```sh
# Inputs: PR_NUMBER; TARGET_REPO (Step 1); BOARD_BYPASS=1 only on --self-record.
# --repo "$TARGET_REPO" is explicit (dEitY719/dotfiles#1405): without it the helper falls back
# to `gh repo view`, which answers `gh repo set-default`, not this skill's
# resolved remote.
_HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh"
[ -f "$_HELPER" ] || _HELPER="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common/functions/gh_project_status.sh"
if [ -r "$_HELPER" ]; then
    export SHELL_COMMON="${_HELPER%/functions/gh_project_status.sh}"
    . "$_HELPER"
    if ! command -v _gh_project_status_sync >/dev/null 2>&1; then
        printf '[gh-pr-approve] %s sourced but _gh_project_status_sync undefined — board sync skipped (#724).\n' \
            "$_HELPER" >&2
    else
        _rc=0
        if [ "${BOARD_BYPASS:-0}" = "1" ]; then
            printf '[gh-pr-approve] self-record: bypassing #393 fail-closed guard for PR #%s (operator intent).\n' \
                "$PR_NUMBER" >&2
            _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1 \
                _gh_project_status_sync pr "$PR_NUMBER" "Approved" --only-from "Backlog,In progress,In review" --repo "$TARGET_REPO" || _rc=$?
        else
            _gh_project_status_sync pr "$PR_NUMBER" "Approved" --only-from "Backlog,In progress,In review" --repo "$TARGET_REPO" || _rc=$?
        fi
        if [ "$_rc" -ne 0 ]; then
            printf '[gh-pr-approve] board sync rc=%s — continuing (soft-fail).\n' "$_rc" >&2
        fi
    fi
fi
# helper missing → board sync silently skipped (NF-1, dEitY719/dotfiles#644).
```

Helper returns `0` on the happy path *and* on a silent no-op (repo has no
projectV2 attachment). `GH_PROJECT_STATUS_SYNC=0` opt-out is absorbed by
the helper itself.

## Report line

Step 5 prints one line so the operator can see what happened:

```text
Board: PR #<N> card -> Approved (only-from "Backlog,In progress,In review")
Board: skipped (rc=<N>) — card may need a manual move
Board: not promoted (request-changes / analysis-only path)
```

## See also

- `references/board-policy.md` — what the `Approved` column means.
- `references/self-pr-handling.md` — the `--self-record` procedure.
- `shell-common/functions/gh_project_status.sh` — dEitY719/dotfiles#393 write-side guard.
- `docs/.ssot/github-project-board.md` — column semantics SSOT.
