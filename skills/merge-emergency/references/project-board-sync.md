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
# helper-fallback NF-1 (#644): silent-skip when helper missing.
# Defense-in-depth (#724): also detect "sourced but function undefined".
_HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh"
[ -f "$_HELPER" ] || _HELPER="${CLAUDE_PLUGIN_ROOT:-$PWD}/lib/vendor/shell-common/functions/gh_project_status.sh"
if [ -r "$_HELPER" ]; then
    export SHELL_COMMON="${_HELPER%/functions/gh_project_status.sh}"
    . "$_HELPER"
    if ! command -v _gh_project_status_sync >/dev/null 2>&1; then
        printf '[gh-pr-merge-emergency] %s sourced but _gh_project_status_sync undefined — board sync skipped (#724).\n' \
            "$_HELPER" >&2
    else
        # --repo "$TARGET_REPO" (Step 1) is explicit (#1405): the helper's
        # `gh repo view` fallback reports `gh repo set-default`, not this
        # skill's resolved remote.
        _gh_project_status_sync pr <PR_NUMBER> "Done" --repo "$TARGET_REPO" || true
    fi
fi
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
