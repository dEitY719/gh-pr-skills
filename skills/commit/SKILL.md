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

## Step 1: Inspect State (parallel) — ALWAYS FIRST

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 5.

Runs **unconditionally** on every invocation, even bare `/gh-pr:commit` with no
conversation context — the working-tree state is the source of truth, so do
NOT ask "what did you change?". In a single message run: `git status` (never
`-uall`), `git diff` (staged + unstaged), `git diff --staged` if anything is
staged, and `git log --oneline -20` (to mimic the repo's commit style).

In that same message, parse `[issue-number] [remote]` (dEitY719/dotfiles#1405) and bind the
GitHub target for Step 5: read `references/github-target.md` and paste its
snippet verbatim (exports `GH_HOST`/`TARGET_REPO`/`TARGET_HOST`/`REMOTE`, dEitY719/dotfiles#1403).

## Step 2: Resolve the Issue Number

First hit wins: (1) explicit all-digit argument (`/gh-pr:commit 123` or "이슈
123번 연결" in the latest message); (2) recent conversation — scan the last ~10
messages for `#N` or "Issue #N created" (gh-issue:create's output); (3) none →
skip the footer, do NOT invent an issue number.

## Step 3: Draft the Commit Message

Read `references/commit-message-format.md` for the message template, HEREDOC
pattern, and `Closes`/`Fixes` rules (`Refs`/`Resolves` forbidden); match the
`git log` style. With no conversation context (manual edits), derive intent
from the diff — paths and names tell you *what* changed; small additions get
a short subject like `chore(aliases): add <name> shortcut` (body optional,
mandatory footers still apply). Only ask the user when the diff is ambiguous
or spans unrelated areas.

## Step 4: Stage and Commit

- Stage only relevant files by name — avoid `git add -A`/`.` to keep secrets
  and unrelated changes out. **Never stage secret-looking files** (`.env`,
  `credentials.json`, keys); if the diff touches such files, stop and warn.
- **NEVER** `--amend` unless explicitly asked. **NEVER** `--no-verify` /
  `--no-gpg-sign`: if a hook fails, fix the cause, re-stage, new commit.
- See `references/commit-message-format.md` for the exact HEREDOC command.

After `git commit` succeeds, emit the step-completion marker so the step-skip
guard (`skill_completion_guard.py`, issue dEitY719/dotfiles#753) can verify this step ran:
`printf '[step:gh-pr-commit/stage-commit] OK\n'`.

## Step 5: AI Metrics + Sync Project Board Status

The ai-metrics comment POST (`GH_DISABLE_AI_METRICS` branch, token formula,
soft-fail) follows [`references/ai-metrics-comment.md`](references/ai-metrics-comment.md).
The project-board sync (`--only-from Backlog` guard, helper-fallback NF-1/dEitY719/dotfiles#724
defense) follows [`references/board-sync.md`](references/board-sync.md) —
skip it entirely when no issue footer was written. After both blocks, emit
`printf '[step:gh-pr-commit/metrics-board-sync] OK\n'`.

## Step 6: Verify

After commit succeeds, run `git status` and report
`Committed <short-hash>: <subject line>` (issue number on a second line if one
was linked), then emit the closing step-skip-guard marker:
`printf '[step:gh-pr-commit/report] OK\n'`.

## Constraints

- One commit per invocation by default. If the diff is clearly two unrelated
  changes, ask the user whether to split before staging.
- Never push (`/gh-pr:create` handles pushing), create empty commits, or edit git config.

## Related Skills

`gh-pr:create` pushes the branch and opens the PR from these commits · `gh-issue:create`
files the issue this commit links to.
