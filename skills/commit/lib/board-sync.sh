#!/usr/bin/env bash
# gh-pr:commit Step 5 (second half) — push the linked Issue card to
# `In progress`, only from `Backlog` (soft-fail).
#
#   GH_HOST=<host> bash skills/commit/lib/board-sync.sh <ISSUE_NUMBER>
#
# Run only when a `Closes|Fixes #N` footer was actually written. GH_HOST must
# be Step 1's export: `_gh_project_status_sync` calls gh itself and takes no
# host argument (dEitY719/dotfiles#1403).
#
# Contract: ALWAYS exits 0, bad arguments included. Diagnostics go to stderr
# with the `[gh-commit]` prefix; the commit itself is unaffected.
# bash, not sh: the vendored helper it sources is written for bash.
# Rationale: references/board-sync.md. Guards: tests/commit-lib.sh,
# tests/plugin-root-tier5.sh §5 (which runs the loader below verbatim).

ISSUE_NUMBER="${1-}"
case "$ISSUE_NUMBER" in
    '' | *[!0-9]*)
        printf '[gh-commit] board sync: ISSUE_NUMBER %s is not a number — skipped; the commit itself is unaffected.\n' "'$ISSUE_NUMBER'" >&2
        exit 0 ;;
esac

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
# shellcheck disable=SC1090  # resolved at run time by the tier ladder above
[ -r "$_HELPER" ] && . "$_HELPER"
if [ "$(command -v _gh_project_status_sync 2>/dev/null)" = _gh_project_status_sync ]; then
    _gh_project_status_sync issue "$ISSUE_NUMBER" "In progress" --only-from Backlog || true
else                                                                                 # tier 5, soft
    if [ -n "$_sc_was" ]; then export SHELL_COMMON="$_sc_prev"; else unset SHELL_COMMON; fi
    printf '[gh-commit] no usable shell-common at %s — board sync skipped; the commit itself is unaffected.\n' \
        "$_HELPER" >&2
fi
unset _sc_was _sc_prev
exit 0
