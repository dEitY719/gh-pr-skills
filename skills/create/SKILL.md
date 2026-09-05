---
name: create
description: >-
  Create a GitHub PR from the current branch, bundling every commit since it
  diverged from base — not just HEAD. Use for /gh-pr:create, "PR 생성", "풀리퀘
  만들어", "지금까지 커밋들로 PR 올려". Creates the PR only — no review, no merge.
license: MIT
allowed-tools: Bash, Read, Grep
metadata:
  model_recommendation:
    tier: haiku
    reason: "gh pr create wrap with body draft; structured commit-range bundling + bounded lint/board mutations"
    claude: prefer
    non_claude: advisory-only
---

# gh-pr:create — Create Pull Request

## Help & Role

If arg #1 is `-h`/`--help`/`help`, output `references/help.md` verbatim and stop
(no API calls). Otherwise: bundle the current branch's commits into a GitHub PR
with a well-structured body, push if needed, return only the PR URL. Accepted
options (`[N]`, `--no-stack`, `--base <branch>`, env): `references/options.md`.

## Step 1: Parse Args, Resolve Base Branch, Gather State

Record `START_TS=$(date +%s)` immediately for Step 4 elapsed-time tracking.

**1a-0 — parse positionals and bind the GitHub target, before any `gh` call:**
read `references/github-target.md` and paste its snippet verbatim. It parses
`[N] [remote] [--no-stack] [--base <branch>]` (#1405) and exports `GH_HOST` /
`GH_REPO` / `TARGET_HOST` / `REMOTE` (#1403). `$REMOTE` drives every `gh` call
**and** every git plumbing call below.

**1a — base via stacked-PR detection:** read `references/stacked-pr.md` and
paste its SSOT functions + dispatch block ("How Step 1 of SKILL.md ties it
together") verbatim. They bind `BASE_BRANCH`, `PARENT_PR`, `ISSUE_NUMBER` and
exit on bad input (`rc=2` mutually-exclusive flags, `rc=3` bad `--base`,
`rc=5` parent PR not `OPEN`). Abort without pushing on any of them.

**1b — gather range + push state:** read `references/branch-state.md` and follow
it end to end: run its "Step 1b state gathering" probes in one message, then
paste its SSOT functions + "How Step 1b ties it together" dispatch block
verbatim. Covers the upstream mispair check feeding Step 5's push policy (F-1)
and the on-the-base-branch recovery (F-2); its "Outcomes" section defines
`not-on-base` / `nothing-to-pr` / `auto-branch-*`.

## Steps 2-3: Analyze ALL Commits + Resolve Issue

The PR body must reflect **every commit** in the range, not just the latest:
read `git log <base>..HEAD` and group by theme (a 5-commit PR mentions all 5).
Issue precedence, same as `gh-pr:commit`: (1) explicit `/gh-pr:create <N>`, (2) recent
conversation `#N`, (3) range commit footers, (4) none → omit the link.

## Step 4 + 4.5: Draft Body, then Lint Guard (pre-push)

Read `references/pr-body-template.md` for title rules and body markdown; match
the language of existing commits. Then follow `references/ai-metrics-footer.md`
verbatim to compute `TOKENS`/`HUMAN_H`/`ELAPSED` and append the footer to `$BODY`
(soft-fail; honours `GH_DISABLE_AI_METRICS=1`, #399). Step 4.5: paste the
"Helper" snippet from `references/lint-guard.md` verbatim — runs against
`$BASE_BRANCH` **before** the Step 5 push, hard-fails on lint errors, auto-skips
on no-tools / empty change set / `GH_PR_LINT_BYPASS=1`.

## Step 5: Push and Create

Read `references/push-and-create.md` for the upstream-state push policy and the
`gh pr create` command (`mktemp` body file, `--assignee @me`, `--base
"$BASE_BRANCH"`). After the URL returns, emit
`printf '[step:gh-pr-create/push-and-create] OK\n'` (step-skip guard, #753).

## Step 6: Apply Labels

Derive labels from conventional-commit types in `git log <base>..HEAD` and PR
scope; apply only labels that already exist (`GH_HOST="$TARGET_HOST" gh label
list --repo "$GH_REPO"`) — never create new ones. Mapping + safe-apply loop:
`references/pr-body-template.md`. After it (all-missing no-op included), emit `printf '[step:gh-pr-create/labels] OK\n'`.

## Step 7: Sync Project Board Status

Push the new PR card to `In review` and correct any linked Issue cards the GitHub
builtin mis-moved there (Issues belong in `In progress`) — paste the snippet from
`references/project-board-sync.md` verbatim. That file also carries the hook
auto-skip narrative, `GH_REPO` requirement, Step 8 report-row mapping, and the
`[step:gh-pr-create/board-sync] OK` marker.

## Step 8: Report

Read `references/report-template.md` for the success/failure report blocks (the
defense-in-depth `Board sync:` row, #747, included) and the closing `[step:gh-pr-create/report] OK` marker. No extra summary — the user opens the URL.

## Constraints

Read `references/constraints.md`: no force-push without approval, default base
only, no AI footer unless the repo already uses one, never skip commits in the
Summary.

## Related Skills

`gh-pr:commit` makes the commits this PR bundles · `gh-pr:review` / `gh-pr:approve` review it · `gh-pr:merge` merges it.
