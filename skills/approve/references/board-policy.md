# Board Status Policy — `Approved` column gate

This is the single-source-of-truth for what the `Approved` column on a
projectV2 board means in this org's workflow, and which guard rails
enforce it.

## Rule

A PR card may only sit in the `Approved` column when GitHub's
`reviewDecision` for that PR equals `APPROVED`. Any other state
(`REVIEW_REQUIRED`, `CHANGES_REQUESTED`, empty) is a policy violation.

The column's purpose: **the PR is already reviewed, and the author is
now deciding whether to actually merge it.** It is a human decision
gate, not a bookkeeping stop.

## Ownership (issue #1350)

`gh-pr:approve` is the **sole skill** writer of this column: no other
skill may promote a card into it, and promotion happens only when a
person explicitly runs `/gh-pr:approve` — see
`references/board-approved-sync.sh.md` for the per-path table and the
`--self-record` bypass. The one non-skill writer is
`.github/workflows/project-board-sync.yml`'s
`pull_request_review.submitted` handler, which covers an external
collaborator's Approve; both writers are enumerated in
`docs/.ssot/github-project-board.md`.

`gh-pr:reply` used to auto-promote after a reply round (its Step 8,
allowlist-gated). That was removed: `agy` / `codex` reviews and
`gh-pr:reply` answers all post as `COMMENTED`, which never changes
`reviewDecision`, so the `""|null|APPROVED` guard passed
unconditionally and BLOCKING PRs landed in `Approved` (PR #1349). The
env var `GH_PR_REPLY_AUTO_APPROVE_REPOS` and its `~/.zshrc.local`
wiring are gone with it.

This rule used to cascade into `gh-pr:merge` as a merge-time refusal.
That cascade was removed in #1513 — see "2. Merge gate (read side)"
below. The column is now advisory for merge purposes; `gh-pr:merge`
gates on `reviewDecision` and CI only.

## Why fail-closed instead of advisory

`reviewDecision == APPROVED` is necessary but not sufficient on this
board:

- Solo / personal repos lack branch protection. `reviewDecision` stays
  empty for self-authored PRs, so a CI-only check would pass without any
  human signal at all.
- Teammate review is captured by the board column, not by GitHub's
  reviewer mechanism — the column is what the team eyes when triaging.

A fail-closed guard on the transition keeps the column meaningful: when
you see a PR in `Approved`, it actually has been through reviewer eyes.
(The merge-side half of this argument no longer holds on a repo with no
reachable approval signal at all — see enforcement point 2.)

## Enforcement points

### 1. Transition into the column (write side)

`shell-common/functions/gh_project_status.sh` rejects any
`_gh_project_status_sync pr <N> "Approved"` call when
`gh pr view --json reviewDecision` returns anything other than
`APPROVED`. Failure mode is `exit 2` with a clear stderr line; bypass is
`_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1` for emergency operator
intent.

This guard was added in #393 along with the verify pair — both are
defenses against the same class of bug (Status drifts away from what the
helper thinks it set).

### 2. Merge gate (read side) — **removed in #1513**

`gh-pr:merge` Step 2-B (added by #397) used to read the current board
Status before merging and refuse anything outside `Approved`, with
`GH_PR_MERGE_SKIP_BOARD_CHECK=1` as the escape. Both the step and the
env var are gone.

The gate was permanently un-satisfiable on `dEitY719/dotfiles`. That
repo has no branch protection and every PR is self-authored, and GitHub
forbids approving your own PR; `agy` / `codex` reviews post as
`COMMENTED`, so `reviewDecision` never becomes `APPROVED` and the
builtin `Code review approved` workflow never fires. With neither the
manual nor the automated promotion path available, no card could ever
reach `Approved`, and every merge was blocked. Adding a
protection-absent exception (as the `reviewDecision` gate has) would
have been equivalent to permanent disablement here, since this repo
never has protection — so the gate was deleted outright rather than
left in place as dead policy.

What remains: enforcement point 1 above is unaffected, and `gh-pr:merge`
Step 2 still hard-stops on a non-empty non-`APPROVED` `reviewDecision`.
On a repo that *does* have branch protection, that Step 2 gate is the
one doing the work.

## Out of scope

- Issue cards never visit `Approved` per `github-project-board.md`;
  guards above only apply when `kind == pr`.
- Repos without a projectV2 attachment are auto-detected and skipped:
  the helper finds zero items and returns 0. No board → no policy →
  legacy CI-only flow (`reviewDecision == APPROVED` still required by
  `gh-pr:merge` Step 2).

## Audit

`gh-audit-builtin-workflows` (shell-common function added in #397)
checks that the asynchronous "Pull request linked to issue" builtin
workflow is OFF on every attached projectV2 — that builtin races with
the deterministic Status transitions and would silently invalidate this
guard.

## See also

- `references/board-approved-sync.sh.md` — Step 4.5 promotion block.
- `shell-common/functions/gh_project_status.sh` — write-side guard impl.
- `../../merge/references/board-policy.md` — cross-link
  (records the #1513 removal of the merge gate).
- `docs/.ssot/github-project-board.md` — column semantics SSOT.
