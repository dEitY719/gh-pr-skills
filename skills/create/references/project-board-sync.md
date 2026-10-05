# Project Board Sync — snippet + narrative

> The executable lives in `lib/project-board-sync.sh <PR_NUMBER>` (relative
> to `skills/create/`; env `GH_HOST`, `GH_REPO`, `REMOTE`). This file is its
> contract and narrative companion — rationale, edge cases, and pointers.
> (The issue dEitY719/dotfiles#747 visual-checklist guarantees are preserved by
> the Step 8 report row.)

## What the script does

1. Detect a PostToolUse hook that already handles this sync — when present,
   print one `board sync delegated to PostToolUse hook` line and skip, to
   avoid triple-syncing (issue dEitY719/dotfiles#390).
2. Otherwise load `gh_project_status.sh` through the SOFT warn-and-skip loader
   (harness-skills#60): a missing helper, or one that defines nothing, is ONE
   `[gh-pr] no usable shell-common at <path>` warning and a skip; the failure
   arm restores `SHELL_COMMON`.
3. PR card -> `In review` (no guard), then each closing Issue ->
   `In progress` (`--only-from "Backlog,Ready,In review"`); every sync `|| true`.

Exit: `0` in every case above. `1` only when `GH_REPO` was empty and the
nested HARD `gh_host.sh` loader that re-resolves it hit tier 5 — a broken
install. A non-numeric argument is one warning, exit 0.


`GH_REPO` should be `owner/repo` (e.g. `dEitY719/dotfiles`) — normally bound
in Step 1a-0. The block re-resolves it from `$REMOTE`'s URL (`origin` by
default, dEitY719/dotfiles#1405) when unset/empty, ahead of both syncs, so neither the PR
card's `--repo` nor the linked-issues loop is left holding an empty value.
It deliberately does **not** fall back to `gh repo view --json
nameWithOwner`: that reads gh CLI's own default repo, which on a dual-host
login names a repo on the other server (dEitY719/dotfiles#1403). `_gh_project_status_sync`
takes no host argument: its `_gh_project_status_ensure_host` keeps an already-
exported `GH_HOST` and otherwise falls back to `_gh_resolve_host` (the
setup-mode mapping, issue dEitY719/dotfiles#804). Step 1a-0's `export GH_HOST` is what makes it
take the *remote's* host rather than the PC's default — the two differ
whenever the PR targets a remote that isn't the setup-mode's usual server.

Opt-out per invocation: `GH_PROJECT_STATUS_SYNC=0`. Repos without a projectV2
board auto-skip silently (helper returns 0).

Track the outcome for Step 8's report row:
- `hook_skip=1` → `[SKIP]: hook auto-skip`
- helper missing or function undefined → `[SKIP]: helper unavailable`
- helper ran, no projectV2 board → `[SKIP]: no projectV2`
- helper ran with at least one card moved → `[OK]: PR card -> "In review"`

Regardless of which branch ran (hook delegate, helper missing, no
projectV2, real sync), emit the step-completion marker so the
step-skip guard recognizes Step 7 was visited:
`printf '[step:gh-pr-create/board-sync] OK\n'`.

After the PR is created, sync cards on the kanban so reviewers see the PR and
the linked Issues are at the right column without a manual drag. Two cards
need to move:

- The new **PR card** → `In review`.
- Each linked **Issue card** (anything matched by `Closes #N` in the PR
  body) → `In progress`, correcting the GitHub builtin's mis-move to
  `In review`.

## Hook auto-skip (issue dEitY719/dotfiles#390)

If a PostToolUse hook is going to do this work, the skill must NOT run the
inline sync — triple-syncing (skill + hook + GitHub builtin) wastes tokens
and widens the race window. The skill detects the hook by file presence
across three paths:

1. `${REPO_ROOT}/.claude/hooks/post-pr-create-status.sh` —
   AgentToolbox-style in-repo hook.
2. `$HOME/.claude/hooks/post-gh-pr-create.sh` — runtime copy.
3. `$HOME/dotfiles/claude/hooks/post-gh-pr-create.sh` — dotfiles SSOT.

When **any** path exists, the inline snippet is skipped and the hook (or
AgentToolbox hook) handles it. When none exist, the inline snippet runs
as a fallback, preserving behavior for environments without hook support.
Idempotence of `_gh_project_status_sync` (verify pair, issue dEitY719/dotfiles#393) absorbs
the case where both a dotfiles hook and an AgentToolbox hook fire.

## Why "In review" with no guard (PR card)

The PR lifecycle is linear. `In review` is the canonical resting state from
the moment a PR opens through approval, so unconditional sync is safe — there
is no prior status that should block the move.

## Why "In progress" for linked Issues (not "In review")

The GitHub builtin "Pull request linked to issue" (project workflow #3) moves
Issue cards to "In review" when a PR is opened with `Closes #N`. However, the
intended Issue lifecycle is `Backlog → In progress → Done` — Issues must never
visit "In review" or "Approved" (issue dEitY719/dotfiles#289).

Calling `_gh_project_status_sync issue … "In progress"` immediately after the
PR is created corrects the builtin's transition. The
`--only-from "Backlog,Ready,In review"` guard explicitly includes `In review`
so we can undo the builtin's mis-move even when it fires before our sync, while
still refusing to drag `Done` Issues backwards if a closed PR is re-opened (dEitY719/dotfiles#309).

## `GH_REPO` requirement

The closing-issues helper (`_gh_pr_closing_issue_numbers`) needs the repo
slug as `owner/repo` (e.g. `dEitY719/dotfiles`). The Step 7 snippet
auto-resolves `GH_REPO` inline when it is unset/empty — added in response to
the PR dEitY719/dotfiles#780 review: an unset `GH_REPO` would otherwise pass an empty string to
`_gh_pr_closing_issue_numbers`, the helper would return immediately, and the
linked-issues sync loop would silently no-op.

That fallback originally used `gh repo view --json nameWithOwner --jq
.nameWithOwner`. Issue dEitY719/dotfiles#1403 replaced it with `_gh_parse_owner_repo_url` over
`git remote get-url "${REMOTE:-origin}"`: `gh repo view` without `--repo`
answers "what is gh CLI's default repo", not "what is git's remote", and on a
PC logged into both github.com and GHES those two disagree silently. Reading
the slug from the remote URL keeps it consistent with the `GH_HOST` bound from
that same URL. Issue dEitY719/dotfiles#1405 then parameterized *which* remote that is —
`$REMOTE`, the `[remote]` positional, `origin` by default — so a PR opened on
`upstream` syncs `upstream`'s board rather than `origin`'s. Still a thin
wrapper — no auth state changes, no API mutation.

## Behavior summary

- **No projectV2 board attached** — the helper auto-detects zero project items
  and silently returns 0. Nothing happens, no error.
- **PR body has no `Closes #N`** — `_gh_pr_closing_issue_numbers` returns
  nothing; the for-loop body never runs. PR sync still proceeds.
- **Opt-out per invocation** — set `GH_PROJECT_STATUS_SYNC=0` in the
  environment to skip both syncs entirely.
- **Helper unavailable** — when `_HELPER` is unreadable, the inline block
  silently skips (NF-1 fallback, dEitY719/dotfiles#644). When the file sources but the
  function is undefined (interactive-guard regression, partial sourcing,
  future rename), an explicit `dEitY719/dotfiles#724` warning is printed and the sync is
  skipped — preventing the silent `rc 127` swallow.

## Where the helper lives

`shell-common/functions/gh_project_status.sh` — shared between `gh-pr:create`,
`gh-pr:reply`, and other PR/issue lifecycle skills. The script **sources**
this file; do not duplicate the helper's implementation. The bash that
*calls* the helper is `lib/project-board-sync.sh`; Step 7 of `SKILL.md` runs it.
