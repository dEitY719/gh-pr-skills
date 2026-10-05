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
    tier: sonnet
    reason: "not a gh pr create wrapper: stacked-PR base detection with three distinct aborts, branch-state recovery (not-on-base / nothing-to-pr / auto-branch), and a body that must theme-group every commit in the range"
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

**1a-0 + 1a — bind the GitHub target, then the base, before any `gh` call** (one Bash call). Parse
`[N] [remote] [--no-stack] [--base <branch>]` (dEitY719/dotfiles#1405); `github-target.sh` exports
`GH_HOST`/`GH_REPO`/`TARGET_HOST`/`REMOTE` (dEitY719/dotfiles#1403) and `$REMOTE` drives every `gh` **and**
git plumbing call below. `stacked-pr.sh` binds `BASE_BRANCH`/`PARENT_PR`/`ISSUE_NUMBER`; abort
without pushing on any non-zero rc (`2` both flags, `3` bad `--base`, `4` ambiguous parent — ask, re-run
with `--base`/`--no-stack`, `5` parent not `OPEN`, `6` parent already stacked). Contracts:
`references/github-target.md`, `references/stacked-pr.md`. Every `lib/` call opens with the first 3 lines:

```bash
_L=""; if [ -n "${HERMES_SKILL_DIR}" ]; then _L="${HERMES_SKILL_DIR}/lib"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then _L="$CLAUDE_PLUGIN_ROOT/skills/create/lib"; fi
[ -n "$_L" ] && [ -d "$_L" ] || { printf '[FAIL] gh-pr:create: lib/ unresolved (%s) - export HERMES_SKILL_DIR=<skill dir> or CLAUDE_PLUGIN_ROOT=<plugin dir>\n' "${_L:-unset}" >&2; exit 1; }
_gt=$(sh "$_L/github-target.sh" "<remote>") || exit 1; eval "$_gt"
_sp=$(bash "$_L/stacked-pr.sh" <args>) || exit $?; eval "$_sp"
```

**1b — gather range + push state:** run the "Step 1b state gathering" probes of
`references/branch-state.md` in one message, then
`BASE_BRANCH=<base> REMOTE=<remote> ISSUE_NUMBER=<N> bash "$_L/branch-state.sh" dispatch`. Its last
line `BRANCH_STATE=` is `not-on-base` / `nothing-to-pr` (stop) / `auto-branch-*` (the F-2
recovery already switched branches); the upstream mispair check feeds Step 5's push policy (F-1).

## Steps 2-3: Analyze ALL Commits + Resolve Issue

Read "Commit coverage and issue precedence" in `references/pr-body-template.md`
before drafting: the every-commit rule and the issue-number precedence chain.

## Step 4 + 4.5: Draft Body, then Lint Guard (pre-push)

Read `references/pr-body-template.md` for title rules and body markdown; match
the language of existing commits. Then follow `references/ai-metrics-footer.md`
verbatim to compute `TOKENS`/`HUMAN_H`/`ELAPSED` and append the footer to `$BODY`
(soft-fail; honours `GH_DISABLE_AI_METRICS=1`, dEitY719/dotfiles#399). Step 4.5, **before** the Step 5
push: `bash "$_L/lint-guard.sh" <BASE_BRANCH>` — exit 1 stops the run (lint errors or a broken
install); auto-skips on no-tools / empty change set / `GH_PR_LINT_BYPASS=1` (`references/lint-guard.md`).

## Step 5: Push and Create

Read `references/push-and-create.md` for the upstream-state push policy
(`bash "$_L/branch-state.sh" push-action <cur> <upstream> <diverged> <remote>`) and the
`gh pr create` command (`mktemp` body file, `--assignee @me`, `--base
"$BASE_BRANCH"`). After the URL returns, emit
`printf '[step:gh-pr-create/push-and-create] OK\n'` (step-skip guard, dEitY719/dotfiles#753).

## Step 6: Apply Labels

Derive and apply labels per "Label derivation (Step 6)" in
`references/pr-body-template.md`. After it (all-missing no-op included), emit `printf '[step:gh-pr-create/labels] OK\n'`.

## Step 7: Sync Project Board Status

PR card to `In review`, linked Issue cards the builtin mis-moved back to `In progress`:
`GH_HOST=<host> GH_REPO=<owner/repo> REMOTE=<remote> bash "$_L/project-board-sync.sh" <PR#>`.
`references/project-board-sync.md` carries the hook auto-skip, the Step 8 report-row
mapping and the `[step:gh-pr-create/board-sync] OK` marker (emitted whatever the outcome).

## Step 8: Report

Read `references/report-template.md` for the success/failure report blocks (the
defense-in-depth `Board sync:` row, dEitY719/dotfiles#747, included) and the closing `[step:gh-pr-create/report] OK` marker. No extra summary — the user opens the URL.

## Constraints

Read `references/constraints.md`: no force-push without approval, default base
only, no AI footer unless the repo already uses one, never skip commits in the
Summary.

## Related Skills

`gh-pr:commit` makes the commits this PR bundles · `gh-pr:review` / `gh-pr:approve` review it · `gh-pr:merge` merges it.
