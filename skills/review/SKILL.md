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
(`references/review-presets.md`). Flags — `--ai <codex|agy|claude|opencode|hermes>`,
`--review <preset>`, `--user <name>` (claude only), `--no-post-comment`,
`--paths <path>`, and `<PR#> [remote]` — are tabled in `references/help.md`.

## Help

If arg #1 is `-h` / `--help` / `help`, read `references/help.md` and
output it verbatim, then stop. No API calls.

## Step 1: Parse Flags + Resolve Target

Delegate to `gh_pr_review_parse` (`shell-common/functions/gh_pr_review.sh`). Argument shape + KR aliases + exit
codes: `references/parser-contract.md` — it also covers `START_TS`, `PR_NUMBER`, and binding `TARGET_REPO` +
`TARGET_HOST` from one remote URL. Every `gh` call below then runs as
`GH_HOST="$TARGET_HOST" gh ... --repo "$TARGET_REPO"`; `--repo` alone carries no host (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407).

## Step 2: Pre-flight

Run these checks before expensive work:

- PR state must be `OPEN` AND not draft → else exit 1 `PR #<N> is <state>; aborting`.
- `command -v <ai-bin>` for the chosen `--ai` → else exit 1 `Required CLI '<name>' not found in PATH`.
- `--ai opencode` and `--ai hermes` each require `_dotfiles_setup_mode == internal`; otherwise
  exit 1 `--ai <name> is internal-PC only (~/.dotfiles-setup-mode != internal)`.
- `gh auth status` returns 0 → else exit 1 with the gh error line.

CI status is not a gate; self-authored PRs are allowed because no decision is submitted.

## Step 3: Load Review Preset

Read `references/review-presets.md`. Build the prompt as
`<common-prompt-prefix>` + `<preset-body for the resolved enum>`.
Normalized enum: `default` / `quick` / `thorough` / `security` /
`performance` (KR-alias normalized in Step 1).

## Step 4: Fetch Review Material

Decide path: if `--paths <path>` (repeatable) was given, always take the
**inline** `gh pr diff` path regardless of PR size — the diff is filtered by
path in `_gh_pr_review_build_prompt`, so a scoped run never routes through
large-diff delegation, and a scope matching no file exits 1 rather than
reviewing an empty diff (dEitY719/dotfiles#1616). Otherwise decide by diff size
(`gh pr view --json additions,deletions`): `≥ 800` lines → follow
`../../approve/references/large-diff-delegation.md`; else inline
`gh pr diff`. Append the diff per `references/ai-cli-invocation.md` and write
`(prompt + diff)` to `PROMPT_FILE`.

Never hardcode or reuse a `PROMPT_FILE`; derive it from
`_gh_pr_review_mktemp_prompt "$ai" "$PR_NUMBER"` and do the write plus Step 5
dispatch in the same Bash tool call. Then `rm -f "$PROMPT_FILE"`.

## Step 5: Dispatch to External CLI

Delegate to `_gh_pr_review_run_ai` (`shell-common/functions/gh_pr_review.sh`).
Invocation shapes, stdout streaming, non-zero handling:
`references/ai-cli-invocation.md` § "Step 5 dispatch procedure".

For `--ai opencode` and `--ai hermes` only: set the Bash tool `timeout`
parameter of that Step 4+5 call to at least `600000` (ms, 10 min). Never
rely on the ambient 2-minute default — it kills the run before the
dispatcher's own 540s bound can fail it cleanly (issue dEitY719/dotfiles#1506).

## Step 6: Post PR Comment (default ON)

Delegate to `_gh_pr_review_build_comment_body` +
`_gh_pr_review_post_comment` (`shell-common/functions/gh_pr_review.sh`).
SSOT body template, posting decision tree, and token/human-h arithmetic:
`references/post-comment.md` § "Step 6 delegation + 3-branch decision tree".

## Step 7: Report

Print exactly one line on success:
`[OK] PR #<N> reviewed by <ai> (--review=<preset>) — comment: <URL or skipped>`.

## Constraints (full rationale: `references/constraints.md`)

- One AI CLI per invocation; closed `--review` enum; raw external output only.
- Never submit decisions, reply to individual comments, edit the PR body, or log CLI stderr to PR comments.
- Honor `GH_DISABLE_AI_METRICS=1` by skipping the entire PR comment.

## Related Skills

`gh-pr:reply` answers each review comment individually · `gh-pr:approve` submits
the approve / request-changes decision · `gh-verify:review-all` fans this skill out
across every reviewer at once.
