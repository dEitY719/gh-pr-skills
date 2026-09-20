# Project Board Sync — push emergency-merged PR card to `Done`

After the admin merge succeeds, sync the PR's project-board card to `Done`.
The emergency path bypasses approval, but it still completes the same PR
lifecycle as a normal merge.

## Why no `--only-from` guard

`Done` is the terminal PR state after merge. Emergency merges may happen from
`In review`, `Approved`, or another in-flight status; all should move forward
to `Done`. Repeating the sync on an already-`Done` card is harmless.

## Snippet

Source the shared helper, then call it with the merged PR number:

```bash
# Soft warn-and-skip loader (harness-skills#60). A missing helper, or one that
# sources but defines nothing (dEitY719/dotfiles#724), skips the board sync with
# ONE warning naming the path — no longer silently (dEitY719/dotfiles#644 NF-1's
# silence hid a broken install).
_HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh" # tier 1
[ -f "$_HELPER" ] || [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] \
    || _HELPER="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common/functions/gh_project_status.sh" # tier 2
_sc_was=${SHELL_COMMON+set} _sc_prev="${SHELL_COMMON-}"                              # save
unset -f _gh_project_status_sync 2>/dev/null || :
unalias _gh_project_status_sync 2>/dev/null || :
export SHELL_COMMON="${_HELPER%/functions/gh_project_status.sh}"                     # before the load
[ -r "$_HELPER" ] && . "$_HELPER"
if [ "$(command -v _gh_project_status_sync 2>/dev/null)" = _gh_project_status_sync ]; then
    # --repo "$TARGET_REPO" (Step 1) is explicit (dEitY719/dotfiles#1405): the helper's
    # `gh repo view` fallback reports `gh repo set-default`, not this
    # skill's resolved remote.
    _gh_project_status_sync pr <PR_NUMBER> "Done" --repo "$TARGET_REPO" || true
else                                                                                 # tier 5, soft
    if [ -n "$_sc_was" ]; then export SHELL_COMMON="$_sc_prev"; else unset SHELL_COMMON; fi
    printf '[gh-pr-merge-emergency] no usable shell-common at %s — board sync skipped; the merge itself is unaffected.\n' \
        "$_HELPER" >&2
fi
unset _sc_was _sc_prev
```

## Behavior

- **No projectV2 board attached** — the helper auto-detects zero project
  items and returns 0.
- **Sync failure** — the helper logs to stderr and returns 0; merge/audit
  success remains the primary outcome.
- **Opt-out per invocation** — set `GH_PROJECT_STATUS_SYNC=0` to skip sync.

## Where the helper lives

`shell-common/functions/gh_project_status.sh` — shared by PR and Issue
lifecycle skills. Do not inline-copy the GraphQL logic.
