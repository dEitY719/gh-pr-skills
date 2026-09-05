---
name: approve
description: >-
  Decide a GitHub PR: approve when clean, request changes on blockers, file
  follow-up issues for the rest. Use for /gh-pr:approve,
  "approve PR 99", "#99 리뷰 승인", "re-review requested". Self-authored PRs can
  never be approved.
license: MIT
allowed-tools: Bash, Read, Grep, Glob, Agent
metadata:
  model_recommendation:
    tier: sonnet
    reason: "PR review judgment — diff analysis, BLOCKER/FOLLOW-UP/PRAISE classification, follow-up issue filing"
    claude: prefer
    non_claude: advisory-only
---

# gh-pr:approve - Review, Approve, or Handle Self-PR

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output it
verbatim, then stop. Help is detected only at arg #1, so `--self-ok -h` is parsed
as unsupported `--self-ok` plus extra args. Positionals (`<PR#> [remote]`) and
flags (`--self-record`, `--admin-merge`, `--squash`/`--rebase`/`--merge`) are
tabled in that same file.

## Step 1: Resolve + Pre-flight Gate (parallel)

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 4.

Parse args, bind the GitHub target (`TARGET_HOST` + `TARGET_REPO` from one remote URL),
then fetch PR metadata in parallel before reading the diff. `references/arg-parsing.md`
holds the "GitHub target" block, the flag table, rejection rules, the parallel fetch
list (incl. the REST-only `rebaseable` field), and gate decisions (stop vs. warn). Self-PR
(`author.login == ME`) follows `references/self-pr-handling.md`; prior `ME` comments trigger re-review mode (verify every prior concern fixed, tracked, or acceptably declined).

## Step 2: Fetch Review Material

Decide path by diff size: `GH_HOST="$TARGET_HOST" gh pr view <N> --repo "$TARGET_REPO" --json additions,deletions`.
When `additions + deletions` meets the threshold in
`references/large-diff-delegation.md`, dispatch an Explore subagent following
that file, skip loading the full diff into the main context, and feed its
BLOCKER/FOLLOW-UP/PRAISE summary into Step 3.

Inline path (below the threshold) — in parallel: `GH_HOST="$TARGET_HOST" gh pr diff <N> --repo "$TARGET_REPO"`, commits JSON,
and the three comment endpoints in `references/review-criteria.md`. Apply that
checklist. In re-review mode, map each prior concern to a fixing commit, tracking
issue, or acceptable author reply.

## Step 3: Classify Findings

Classify each concern as **BLOCKER**, **FOLLOW-UP**, or **PRAISE**. Praise
for approvals must cite concrete diff locations. Path selection:

- Non-self, 0 BLOCKER, 0 FOLLOW-UP: **4a** clean LGTM.
- Non-self, 0 BLOCKER, at least 1 FOLLOW-UP: **4b** approve with issues.
- Non-self, at least 1 BLOCKER: **4c** request changes.
- Self-authored PR: use the selected path from `references/self-pr-handling.md`.

## Step 4: Submit Review or Self-PR Action

Use `references/approval-templates.md` for commands and body templates; match the
PR's dominant language.

- **4a** Submit `gh pr review --approve`.
- **4b** Create one issue per FOLLOW-UP, post one linking PR comment, then submit
  `gh pr review --approve`.
- **4c** Submit `gh pr review --request-changes`; blockers stay on the PR.
- Self-authored PR: never approve. Use analysis-only, `--self-record`, or
  `--admin-merge` exactly as specified in `references/self-pr-handling.md`.

After submitting the review (any path), post a separate ai-metrics PR comment —
`references/ai-metrics.md` has the command, footer, and `GH_DISABLE_AI_METRICS=1` skip path (dEitY719/dotfiles#399 / dEitY719/dotfiles#403).

## Step 4.5: Promote the Board Card (soft-fail)

Sole owner of the `Approved` column (dEitY719/dotfiles#1350): on 4a / 4b / self-PR `--self-record`,
sync the card per `references/board-approved-sync.sh.md` (`--self-record` needs the dEitY719/dotfiles#393 single-call bypass).

## Step 5: Verify and Report

Re-fetch `reviewDecision` + `mergeStateStatus`; for `--admin-merge`, also `state`
and `mergeCommit`. Report status, blocker/follow-up counts, issue links, merge
state, the Step 4.5 board line, and PR URL — plus the conflict warning if the PR had `mergeable: CONFLICTING` or `rebaseable: false`. For `--self-record`, confirm `reviewDecision` did not become `APPROVED`.

## Constraints

- Never approve without reading the diff, nor approve your own PR — GitHub blocks
  self-approval server-side and no token or flag can bypass it. Never accept
  `--self-ok`; it describes an impossible operation.
- Never fabricate follow-ups. Each issue must represent a defensible concern.
- Never merge a colleague's PR. `--admin-merge` is self-PR only.
- No labels/milestones unless `gh label list` confirms the label exists.
- Never call `gh` without both `GH_HOST="$TARGET_HOST"` and `--repo "$TARGET_REPO"` (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407) — `--repo` alone follows gh CLI's own default host, not git's remote.
- Never promote a card to `Approved` on the 4c / analysis-only / `--admin-merge` paths.

## Related Skills

`gh-pr:review` collects a second opinion without deciding · `gh-pr:reply` answers
review comments · `gh-pr:merge` merges once this skill has approved.
