---
name: commit
description: >-
  Create a git commit for the current changes in the repo's style, auto-linking
  a GitHub issue number. Use for /gh-pr:commit, "커밋해", "지금까지 작업
  커밋", "이슈 N번 연결해서 커밋". Commits only — never pushes and never opens a
  PR (gh-pr:create).
license: MIT
allowed-tools: Bash, Read, Grep
metadata:
  model_recommendation:
    tier: haiku
    reason: "git commit wrapping, structured"
    claude: prefer
    non_claude: advisory-only
---

# gh-pr:commit — Git Commit with Issue Linking

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Stage the relevant changes and create a new git commit in the repo's commit
style, with a `Closes #N` / `Fixes #N` footer when a GitHub issue is known.
`Refs` / `Resolves` / `See` / `References` keywords are forbidden — they break
GitHub auto-close and project-board automation (see issue dEitY719/dotfiles#392).

**Stop-on-error policy** — HARD (`[FAIL]`, stop): a secret-looking file in the diff, or nothing to stage. A failing hook: fix the cause and re-commit, at most 2 retries, then `[FAIL]` and stop. SOFT (warn, continue): Step 5 board sync and ai-metrics comment.

## Step 1: Inspect State (parallel) — ALWAYS FIRST

Record `START_TS=$(date +%s)` immediately (Step 5 elapsed time). Runs **unconditionally** — the working tree is the source of truth. In a single
message run: `git status` (never `-uall`), `git diff` (staged + unstaged),
`git diff --staged` if anything is staged, and `git log --oneline -20` (to
mimic the repo's commit style).

In that same message, parse `[issue-number] [remote]` (dEitY719/dotfiles#1405) and bind the GitHub
target for Step 5 (`GH_HOST`/`TARGET_REPO`/`TARGET_HOST`/`REMOTE`, dEitY719/dotfiles#1403; contract:
`references/github-target.md`). Every `lib/` call in this skill opens with the first three lines:

```bash
_L=""; if [ -n "${HERMES_SKILL_DIR}" ]; then _L="${HERMES_SKILL_DIR}/lib"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then _L="$CLAUDE_PLUGIN_ROOT/skills/commit/lib"; fi
[ -n "$_L" ] && [ -d "$_L" ] || { printf '[FAIL] gh-pr:commit: lib/ unresolved (%s) - export HERMES_SKILL_DIR=<skill dir> or CLAUDE_PLUGIN_ROOT=<plugin dir>\n' "${_L:-unset}" >&2; exit 1; }
_gt=$(sh "$_L/github-target.sh" "<remote>") || exit 1; eval "$_gt"
```

## Step 2: Resolve the Issue Number

First hit wins: (1) explicit all-digit argument (`/gh-pr:commit 123` or "이슈 123번 연결"); (2) the last
~10 messages' `#N` or "Issue #N created" (gh-issue:create); (3) none → skip the footer, never invent one.

## Step 3: Draft the Commit Message

Read `references/commit-message-format.md` for the template, HEREDOC pattern, and `Closes`/`Fixes` rules
(`Refs`/`Resolves` forbidden); match the `git log` style. With no conversation context, derive intent from
the diff (small additions: a short subject like `chore(aliases): add <name> shortcut`, mandatory footers
still apply). Only ask the user when the diff is ambiguous or spans unrelated areas.

## Step 4: Stage and Commit

- Stage only relevant files by name — avoid `git add -A`/`.` to keep secrets
  and unrelated changes out. **Never stage secret-looking files** (`.env`,
  `credentials.json`, keys); if the diff touches one, stop with a `[FAIL]` report.
- **NEVER** `--amend` unless asked. **NEVER** `--no-verify` / `--no-gpg-sign` (hook failure: policy above).
- See `references/commit-message-format.md` for the exact HEREDOC command.

After `git commit` succeeds, emit the step-skip-guard marker (`skill_completion_guard.py`,
dEitY719/dotfiles#753): `printf '[step:gh-pr-commit/stage-commit] OK\n'`.

## Step 5: AI Metrics + Sync Project Board Status

The ai-metrics comment POST (`GH_DISABLE_AI_METRICS` branch, token formula,
soft-fail) follows [`references/ai-metrics-comment.md`](references/ai-metrics-comment.md).
Board sync — only when an issue footer was written (`--only-from Backlog`, always exit 0; contract:
[`references/board-sync.md`](references/board-sync.md)): after the Step 1 locator lines, run
`GH_HOST="<host>" bash "$_L/board-sync.sh" <ISSUE_NUMBER>`. After both, emit
`printf '[step:gh-pr-commit/metrics-board-sync] OK\n'`.

## Step 6: Verify

After commit succeeds, run `git status`, print the report in
[`references/report-template.md`](references/report-template.md), then emit the
closing step-skip-guard marker: `printf '[step:gh-pr-commit/report] OK\n'`.

## Constraints

- One commit per invocation by default. If the diff is clearly two unrelated
  changes, ask the user whether to split before staging.
- Never push (`/gh-pr:create` handles pushing), create empty commits, or edit git config.

## Related Skills

`gh-pr:create` pushes the branch and opens the PR from these commits · `gh-issue:create` files the issue this commit links to.
