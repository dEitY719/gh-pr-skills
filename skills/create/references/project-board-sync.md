# Project Board Sync — snippet + narrative

> **Canonical executable snippet lives in this file** (below). `SKILL.md`
> Step 7 points here and the model pastes the snippet verbatim. This file
> is both the source of the bash and its narrative companion — rationale,
> edge cases, and pointers. (Relocated from inline Step 7 for progressive
> disclosure; the issue #747 visual-checklist guarantees are preserved by
> the Step 8 report row, not by inlining the bash.)

## Executable snippet (paste verbatim into Step 7)

First, detect a PostToolUse hook that already handles this sync — when
present, skip the inline call to avoid triple-syncing (issue #390):

```bash
hook_skip=0
for hook_path in \
    "${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}/.claude/hooks/post-pr-create-status.sh" \
    "$HOME/.claude/hooks/post-gh-pr-create.sh" \
    "$HOME/dotfiles/claude/hooks/post-gh-pr-create.sh"
do
    if [ -x "$hook_path" ]; then
        hook_skip=1
        printf '[gh-pr] board sync delegated to PostToolUse hook (%s) — skipping inline.\n' "$hook_path" >&2
        break
    fi
done

if [ "$hook_skip" -eq 0 ]; then
    # helper-fallback NF-1 (#644): silent-skip when helper missing.
    # Defense-in-depth (#724): also detect "[ -r ] passes but function never
    # defined" (interactive-guard regression, partial sourcing, future rename).
    # `|| true` would otherwise absorb `command not found` (rc 127) and the
    # entire reconciliation would silently no-op — the failure mode from #724.
    _HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh"
    [ -f "$_HELPER" ] || _HELPER="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common/functions/gh_project_status.sh"
    if [ -r "$_HELPER" ]; then
        export SHELL_COMMON="${_HELPER%/functions/gh_project_status.sh}"
        . "$_HELPER"
        if ! command -v _gh_project_status_sync >/dev/null 2>&1; then
            printf '[gh-pr] %s sourced but _gh_project_status_sync undefined — board sync skipped (#724).\n' \
                "$_HELPER" >&2
        else
            # Auto-resolve GH_REPO when unset/empty so neither the PR sync
            # below nor the linked-issues loop is left to the helper's
            # `gh repo view` auto-detect (PR #780 review, #1405).
            if [ -z "${GH_REPO:-}" ]; then
                # Re-resolve from git's remote, never from `gh repo view`
                # (which answers gh CLI's default repo — wrong host on a
                # dual-host login, #1403). The remote is parameterized: it is
                # $REMOTE, the [remote] positional bound in Step 1a-0, `origin`
                # by default (#1405). Source gh_host.sh explicitly:
                # gh_project_status.sh only sources it on the GH_HOST-unset
                # path, which Step 1a-0's export already bypassed.
                _SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"
                [ -f "$_SC/functions/gh_host.sh" ] || _SC="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common"
                [ -f "$_SC/functions/gh_host.sh" ] || {
                    printf '[gh-pr:create] shell-common not found under %s. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
                        "$_SC" >&2
                    return 1 2>/dev/null || exit 1
                }
                export SHELL_COMMON="$_SC"
                . "$_SC/functions/gh_host.sh"
                GH_REPO=$(_gh_parse_owner_repo_url "$(git remote get-url "${REMOTE:-origin}")" 2>/dev/null || true)
            fi
            _gh_project_status_sync pr "$PR_NUMBER" "In review" --repo "$GH_REPO" || true
            for _issue in $(_gh_pr_closing_issue_numbers "$PR_NUMBER" "$GH_REPO" 2>/dev/null || true); do
                _gh_project_status_sync issue "$_issue" "In progress" \
                    --only-from "Backlog,Ready,In review" || true
            done
        fi
    fi
fi
```

`GH_REPO` should be `owner/repo` (e.g. `dEitY719/dotfiles`) — normally bound
in Step 1a-0. The block re-resolves it from `$REMOTE`'s URL (`origin` by
default, #1405) when unset/empty, ahead of both syncs, so neither the PR
card's `--repo` nor the linked-issues loop is left holding an empty value.
It deliberately does **not** fall back to `gh repo view --json
nameWithOwner`: that reads gh CLI's own default repo, which on a dual-host
login names a repo on the other server (#1403). `_gh_project_status_sync`
takes no host argument: its `_gh_project_status_ensure_host` keeps an already-
exported `GH_HOST` and otherwise falls back to `_gh_resolve_host` (the
setup-mode mapping, issue #804). Step 1a-0's `export GH_HOST` is what makes it
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

## Hook auto-skip (issue #390)

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
Idempotence of `_gh_project_status_sync` (verify pair, issue #393) absorbs
the case where both a dotfiles hook and an AgentToolbox hook fire.

## Why "In review" with no guard (PR card)

The PR lifecycle is linear. `In review` is the canonical resting state from
the moment a PR opens through approval, so unconditional sync is safe — there
is no prior status that should block the move.

## Why "In progress" for linked Issues (not "In review")

The GitHub builtin "Pull request linked to issue" (project workflow #3) moves
Issue cards to "In review" when a PR is opened with `Closes #N`. However, the
intended Issue lifecycle is `Backlog → In progress → Done` — Issues must never
visit "In review" or "Approved" (issue #289).

Calling `_gh_project_status_sync issue … "In progress"` immediately after the
PR is created corrects the builtin's transition. The
`--only-from "Backlog,Ready,In review"` guard explicitly includes `In review`
so we can undo the builtin's mis-move even when it fires before our sync, while
still refusing to drag `Done` Issues backwards if a closed PR is re-opened (#309).

## `GH_REPO` requirement

The closing-issues helper (`_gh_pr_closing_issue_numbers`) needs the repo
slug as `owner/repo` (e.g. `dEitY719/dotfiles`). The Step 7 snippet
auto-resolves `GH_REPO` inline when it is unset/empty — added in response to
the PR #780 review: an unset `GH_REPO` would otherwise pass an empty string to
`_gh_pr_closing_issue_numbers`, the helper would return immediately, and the
linked-issues sync loop would silently no-op.

That fallback originally used `gh repo view --json nameWithOwner --jq
.nameWithOwner`. Issue #1403 replaced it with `_gh_parse_owner_repo_url` over
`git remote get-url "${REMOTE:-origin}"`: `gh repo view` without `--repo`
answers "what is gh CLI's default repo", not "what is git's remote", and on a
PC logged into both github.com and GHES those two disagree silently. Reading
the slug from the remote URL keeps it consistent with the `GH_HOST` bound from
that same URL. Issue #1405 then parameterized *which* remote that is —
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
  silently skips (NF-1 fallback, #644). When the file sources but the
  function is undefined (interactive-guard regression, partial sourcing,
  future rename), an explicit `#724` warning is printed and the sync is
  skipped — preventing the silent `rc 127` swallow.

## Where the helper lives

`shell-common/functions/gh_project_status.sh` — shared between `gh-pr:create`,
`gh-pr:reply`, and other PR/issue lifecycle skills. The skill **sources**
this file; do not duplicate the helper's implementation. The bash that
*calls* the helper lives in the "Executable snippet" section above; Step 7
of `SKILL.md` points here and the model pastes it verbatim.
