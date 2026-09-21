---
name: review
description: >-
  Delegate a GitHub PR review to one external AI CLI and post one aggregate
  comment. Use for /gh-pr:review, "PR 99 코덱스에 리뷰 시켜", "agy 한테 2차 의견 받아",
  "second-opinion review on PR 42". No approve/request-changes, no per-comment replies.
license: MIT
allowed-tools: Bash, Read, Grep, Glob, Agent
metadata:
  model_recommendation:
    tier: sonnet
    reason: "dispatches to external AI CLI; prompt assembly + diff routing + comment posting; moderate orchestration, code judgment delegated"
    claude: prefer
    non_claude: advisory-only
---

# gh-pr:review — Delegate PR Review to an External AI CLI

## Role

Gather a second-opinion review on a GitHub PR from one external AI CLI
(`codex`/`agy`/`claude`/`opencode`/`hermes`), stream raw output, and post one PR
comment by default. **Never** submits `--approve` / `--request-changes` (that is
`gh-pr:approve`) and **never** replies to individual review comments (that is
`gh-pr:reply`). Every preset requires a critical stance
(`references/review-presets.md`). Arguments and flags: `references/help.md`.

## Help

If arg #1 is `-h` / `--help` / `help`, read `references/help.md` and
output it verbatim, then stop. No API calls.

## Step 1: Parse Flags + Resolve Target

Delegate to `gh_pr_review_parse` (`functions/gh_pr_review.sh` — the dotfiles `shell-common` checkout takes
precedence, the vendored `lib/vendor/shell-common/` copy is the fallback; order in `references/parser-contract.md`).
Argument shape + KR aliases + exit codes: `references/parser-contract.md` — it also covers `START_TS`,
`PR_NUMBER`, and binding `TARGET_REPO` + `TARGET_HOST` from one remote URL. Every `gh` call below then runs as
`GH_HOST="$TARGET_HOST" gh ... --repo "$TARGET_REPO"`; `--repo` alone carries no host (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407).

## Step 2: Pre-flight

Run these checks before expensive work:

Read `references/preflight.md` and apply every gate it lists — PR state, the
`--ai` binary, the internal-PC restriction, `gh auth status`, and what is not a gate.

## Step 3: Load Review Preset

Read `references/review-presets.md`. Build the prompt as
`<common-prompt-prefix>` + `<preset-body for the resolved enum>`.
Normalized enum: `default` / `quick` / `thorough` / `security` /
`performance` (KR-alias normalized in Step 1).

## Step 4: Fetch Review Material

Read `references/review-material.md` and follow it: the `--paths` inline rule,
the diff-size branch on the threshold in
`../approve/references/large-diff-delegation.md`, and the `PROMPT_FILE` rule.

## Step 5: Dispatch to External CLI

Delegate to `_gh_pr_review_run_ai` (same file as Step 1). Invocation shapes, stdout
streaming, non-zero handling: `references/ai-cli-invocation.md` § "Step 5 dispatch procedure".

For `--ai opencode` and `--ai hermes` only: set the Bash tool `timeout`
parameter of that Step 4+5 call to at least `600000` (ms, 10 min). Never
rely on the ambient 2-minute default — it kills the run before the
dispatcher's own 540s bound can fail it cleanly (issue dEitY719/dotfiles#1506).

## Step 6: Post PR Comment (default ON)

Delegate to `_gh_pr_review_build_comment_body` + `_gh_pr_review_post_comment`. SSOT body
template, posting decision tree, token/human-h arithmetic: `references/post-comment.md`
§ "Step 6 delegation + 3-branch decision tree".

## Step 7: Report

Success — two lines:
`[OK] PR #<N> reviewed by <ai> (--review=<preset>) — comment: <URL or skipped>`
`Next: /gh-pr:reply <N> (address the findings) or /gh-pr:approve <N>`.

Failure — every Step 2 pre-flight `exit 1` prints one line first:
`[FAIL] PR #<N> not reviewed — <reason>`.

## Constraints (full rationale: `references/constraints.md`)

- One AI CLI per invocation; closed `--review` enum; raw external output only.
- Never submit decisions, reply to individual comments, edit the PR body, or log CLI stderr to PR comments.
- Honor `GH_DISABLE_AI_METRICS=1` by skipping the entire PR comment.

## Related Skills

`gh-pr:reply` answers each review comment individually · `gh-pr:approve` submits
the approve / request-changes decision · `gh-verify:review-all` fans this skill out
across every reviewer at once.
