# gh-pr:approve — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | PR number, or `-h`/`--help`/`help` | required unless current branch has a PR | Target PR, e.g. `99` |
| 2 | remote name | `origin` | Git remote for the target repo |

### Flags

| Flag | Description |
|------|-------------|
| `--self-record` | For a self-authored PR, read the diff and leave a comment-only review record, then promote the board card to `Approved`. This does not satisfy review-based branch protection. |
| `--admin-merge` | For a self-authored PR, read the diff and merge with `gh pr merge --admin` when there are no blockers. Requires admin rights. |
| `--squash`, `--rebase`, `--merge` | Optional merge strategy for `--admin-merge`. |

## Usage

- `/gh-pr:approve 99` — review PR #99 on `origin`
- `/gh-pr:approve 99 upstream` — PR #99 on `upstream`'s repo
- `/gh-pr:approve` — review the PR open on the current branch
- `/gh-pr:approve 99 --self-record` — record self-PR analysis without approval
- `/gh-pr:approve 99 --admin-merge --squash` — review, then admin-merge a clean self-PR
- `/gh-pr:approve -h` / `--help` / `help` — print this help

## What the skill does

1. Pre-flight gate — checks PR state, draft, author, merge conflicts, required CI.
   Stops on non-open PR (closed or merged), draft, or required-check failure. Warns (but continues) on merge
   conflicts — the warning is prepended to the review body and included in the final report.
2. Fetches diff, commits, and all three comment endpoints (inline / issue / review).
3. Reviews against `references/review-criteria.md` — correctness, conventions, security,
   performance, tests. If you previously reviewed this PR, enters re-review mode and
   verifies every prior concern was addressed.
4. Classifies findings as BLOCKER, FOLLOW-UP, or PRAISE.
5. Submits the review:
   - 0 BLOCKER, 0 FOLLOW-UP → **Approve with LGTM** + specific compliments.
   - 0 BLOCKER, ≥1 FOLLOW-UP → files each follow-up as a GitHub issue, posts one PR
     comment linking them, then approves. Keeps the AI-driven issue workflow intact.
   - ≥1 BLOCKER → **Request changes** with per-blocker file:line pointers. Blockers
     stay on the PR so the author's next push triggers natural re-review.
6. Promotes the project-board card to `Approved` (from any pre-merge column) — but only on the
   approve paths and on `--self-record`. This skill is the sole owner of the
   `Approved` column (#1350); `gh-pr:reply` no longer auto-promotes.
7. Re-fetches `reviewDecision` + `mergeStateStatus` and reports a compact summary
   (plus diagnosis if merge is still blocked for reasons outside your review).

## Self-authored PRs

GitHub permanently blocks same-user self-approval server-side. The failing
API error is:

```text
Review Can not approve your own pull request
```

`--self-ok` is not supported. No token, PAT, prompt, freeform flag, or option
combination can make the same GitHub user approve their own PR.

Legitimate alternatives:

1. `gh pr merge --admin` — bypass branch protection and merge with admin rights.
2. `gh pr review --comment` — preserve review analysis as a comment-only review.
3. `gh pr comment` — preserve the same analysis as a normal PR comment.
4. Request an external reviewer — the normal path that satisfies review rules.

## What the skill won't do

- Approve your own PR.
- Accept `--self-ok`.
- Approve without reading the diff.
- Merge a colleague's PR (author decides). `--admin-merge` is only for self-authored PRs.
- Create follow-up issues for trivia that don't justify a tracked item.
- Attach labels/milestones to follow-up issues unless the label already exists in the repo.
