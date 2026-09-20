# Board Sync — gh-pr:commit Step 5 (second half)

Sync the project board **only** when the commit message contains
`Closes|Fixes #N` (i.e. the issue number resolved in Step 2 was actually
written into the footer). Push the linked Issue's card to `In progress`,
but only when its current Status is `Backlog`.

The `--only-from Backlog` guard is mandatory: `/gh-pr:commit` is invoked
many times per branch (initial commit + follow-up fix commits), and after
a PR opens the issue moves to `In review`; without the guard a follow-up
fix commit would bounce it back to `In progress`.

Skip the board sync entirely when no issue footer was written.

`_gh_project_status_sync` issues its own `gh api` calls and takes no host
argument — it reads `GH_HOST` from the environment. Step 1's
`export GH_HOST="$TARGET_HOST"` is therefore load-bearing here: without it the
board mutation goes to gh CLI's default host on a dual-host login (dEitY719/dotfiles#1403).
That host comes from the `[remote]` positional's URL (`$REMOTE`, default
`origin`), so `/gh-pr:commit <N> upstream` syncs `upstream`'s board (dEitY719/dotfiles#1405).

```bash
# Soft warn-and-skip loader (harness-skills#60). A missing helper, or one that
# sources but defines nothing (interactive-guard regression, partial sourcing,
# a rename), skips the board sync with ONE warning naming the path — no longer
# silently (dEitY719/dotfiles#644 NF-1's silence hid a broken install). Without
# the proof `_gh_project_status_sync` expands to nothing, `command not found`
# (rc 127) is absorbed by `|| true`, and the sync no-ops — dEitY719/dotfiles#724.
_HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh" # tier 1
[ -f "$_HELPER" ] || [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] \
    || _HELPER="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common/functions/gh_project_status.sh" # tier 2
_sc_was=${SHELL_COMMON+set} _sc_prev="${SHELL_COMMON-}"                              # save
unset -f _gh_project_status_sync 2>/dev/null || :
unalias _gh_project_status_sync 2>/dev/null || :
export SHELL_COMMON="${_HELPER%/functions/gh_project_status.sh}"                     # before the load
[ -r "$_HELPER" ] && . "$_HELPER"
if [ "$(command -v _gh_project_status_sync 2>/dev/null)" = _gh_project_status_sync ]; then
    _gh_project_status_sync issue <ISSUE_NUMBER> "In progress" --only-from Backlog || true
else                                                                                 # tier 5, soft
    if [ -n "$_sc_was" ]; then export SHELL_COMMON="$_sc_prev"; else unset SHELL_COMMON; fi
    printf '[gh-commit] no usable shell-common at %s — board sync skipped; the commit itself is unaffected.\n' \
        "$_HELPER" >&2
fi
unset _sc_was _sc_prev
```

If the repo has no projectV2 board (auto-detected) the helper silently
returns 0. Opt out with `GH_PROJECT_STATUS_SYNC=0`.

After both blocks (metrics post + board sync), regardless of whether the
post happened, was skipped via `GH_DISABLE_AI_METRICS=1`, or the board
sync ran or no-op'd, emit the step-completion marker so the step-skip
guard recognizes Step 5 was visited:
`printf '[step:gh-pr-commit/metrics-board-sync] OK\n'`.
