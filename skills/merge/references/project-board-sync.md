# Project Board Sync — reconcile board cards after merge

`/gh-pr:merge` performs two independent reconciliations after a
successful merge:

1. **PR card → `Done`** — closes the gap reported in #248 where the
   merged PR card stayed at `Approved`.
2. **Linked Issue cards → `Done`** — closes the gap reported in #250
   where Issue cards stayed at `In review` after auto-close.

Both run from the shared helper
`shell-common/functions/gh_project_status.sh`. Failures never block
the merge report — the helper logs to stderr and returns 0.

## (1) PR card → `Done`

```bash
# helper-fallback NF-1 (#644): silent-skip when helper missing.
# Defense-in-depth (#724): also detect "sourced but function undefined".
_HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh"
if [ -r "$_HELPER" ]; then
    . "$_HELPER"
    if ! command -v _gh_project_status_sync >/dev/null 2>&1; then
        printf '[gh-pr-merge] %s sourced but _gh_project_status_sync undefined — board sync skipped (#724).\n' \
            "$_HELPER" >&2
    else
        # --repo is explicit (#1405) — the helper's auto-detect answers
        # `gh repo set-default`, not the remote Step 1 resolved.
        _gh_project_status_sync pr "$PR_NUMBER" "Done" --repo "$TARGET_REPO" || true
    fi
fi
```

`Done` is the terminal PR state after merge, regardless of which
column the card was in (`In review`, `Approved`, or `In progress` if a
`Changes requested` loop was still pending). No `--only-from` guard is
needed; repeating the sync on an already-`Done` card is a no-op.

## (2) Linked Issue cards → `Done`

GitHub Projects v2 builtin workflows are best-effort only. The
`Item closed` workflow that should move closed Issue cards to `Done`
occasionally drops events, leaving Issue cards stuck at `In review`
even though the Issue itself is `CLOSED`. Concrete observation:
`dEitY719/dotfiles` Issue #239 stayed at `In review` after PR #241
merged at 2026-04-28T03:24:34Z — 16 of 17 other Issues closed around
the same time on the same board moved to `Done` correctly, ruling out
a setup problem and pointing at transient delivery loss (issue #250).

`/gh-pr:merge` is the only natural surface that knows which Issues
will auto-close from a merge — they are listed in the PR's
`closingIssuesReferences` (Closes / Fixes / Resolves keywords).

The closing-issue list comes from a shared helper rather than
`gh pr view --json closingIssuesReferences`:
`gh` 2.45.0 (and earlier) does not include `closingIssuesReferences`
in `pr view --json`'s allow-list and exits with "Unknown JSON field"
(#264). The `_gh_pr_closing_issue_numbers` helper in
`shell-common/functions/gh_project_status.sh` issues a direct GraphQL
query, which is supported across all `gh` versions that ship the
`api graphql` subcommand.

```bash
# Wrap inside the same [ -r "$_HELPER" ] block from step (1) so the closing-issue
# helper is only called after the source succeeded. With the helper missing
# (NF-1, #644) OR sourced-but-function-undefined (#724) the entire
# reconciliation is silently skipped — both gates live in step (1).
for _issue in $(_gh_pr_closing_issue_numbers "$PR_NUMBER" "$TARGET_REPO" 2>/dev/null || true); do
    _gh_project_status_sync issue "$_issue" "Done" \
        --only-from "Backlog,In progress,In review" --repo "$TARGET_REPO" || true
done
```

The `--only-from` whitelist enforces three properties:

- An Issue already at `Done` (builtin fired this round) is left alone —
  no churn, no duplicate update.
- Issue cards never visit `Approved` per
  `docs/.ssot/github-project-board.md`; if one shows up there, it
  is a manual override worth investigating, so the helper skips rather
  than silently overwriting.
- Empty current Status (card never mounted on the board) is also
  skipped, so this never accidentally adds boards to repos that don't
  have one.

## When either step does nothing

- PR body has no `Closes / Fixes / Resolves #N` →
  `closingIssuesReferences` is empty → step (2) loop body never runs.
  Step (1) still runs.
- Repo has no projectV2 board attached → helper finds zero project
  items and silently returns 0 for both steps.
- `GH_PROJECT_STATUS_SYNC=0` set in environment → opt-out, helper
  returns immediately for both steps.
- For step (2) only: Issue card already at `Done` → helper skips per
  `--only-from` guard.

## Where the helper lives

`shell-common/functions/gh_project_status.sh` — shared with `gh-pr:create`,
`gh-pr:reply`, `gh-pr:commit`, `gh-flow:issue`, and `gh-pr:merge-emergency`.
Source the file each invocation; do not inline-copy the snippet so a
single fix propagates everywhere.
