#!/usr/bin/env bash
# gh-pr:approve Step 4.5 — promote the PR card to `Approved` (soft-fail).
#
#   TARGET_HOST=<host> TARGET_REPO=<owner/repo> \
#       bash skills/approve/lib/board-approved-sync.sh <PR_NUMBER> [--self-record]
#
# Run only on 4a / 4b / self-PR `--self-record` (table + rationale:
# references/board-approved-sync.sh.md). `--self-record` carries the
# single-call dEitY719/dotfiles#393 bypass; nothing else does.
#
# Contract: ALWAYS exits 0, bad arguments included. Every diagnostic goes to
# stderr with the `[gh-pr-approve]` prefix; the verdict itself is unaffected.
# bash, not sh: the vendored helper it sources is written for bash.
#
# Regression guards: tests/approve-lib.sh, tests/plugin-root-tier5.sh §5.

PR_NUMBER="${1-}"
BOARD_BYPASS=0
case "${2-}" in
    '') ;;
    --self-record) BOARD_BYPASS=1 ;;
    *) printf '[gh-pr-approve] board sync: unknown flag %s — skipped (soft-fail).\n' "$2" >&2; exit 0 ;;
esac
case "$PR_NUMBER" in
    '' | *[!0-9]*) printf '[gh-pr-approve] board sync: PR_NUMBER %s is not a number — skipped (soft-fail).\n' "'$PR_NUMBER'" >&2; exit 0 ;;
esac
if [ -z "${TARGET_HOST:-}" ] || [ -z "${TARGET_REPO:-}" ]; then
    printf '[gh-pr-approve] board sync: TARGET_HOST and TARGET_REPO must both be set (dEitY719/dotfiles#1403) — skipped (soft-fail).\n' >&2
    exit 0
fi
# The helper calls gh itself and takes no host argument (dEitY719/dotfiles#1403).
export GH_HOST="$TARGET_HOST"

# --repo "$TARGET_REPO" is explicit (dEitY719/dotfiles#1405): without it the helper falls back
# to `gh repo view`, which answers `gh repo set-default`, not this skill's
# resolved remote.
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
    _rc=0
    if [ "$BOARD_BYPASS" = "1" ]; then
        printf '[gh-pr-approve] self-record: bypassing #393 fail-closed guard for PR #%s (operator intent).\n' \
            "$PR_NUMBER" >&2
        _GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS=1 \
            _gh_project_status_sync pr "$PR_NUMBER" "Approved" --only-from "Backlog,In progress,In review" --repo "$TARGET_REPO" || _rc=$?
    else
        _gh_project_status_sync pr "$PR_NUMBER" "Approved" --only-from "Backlog,In progress,In review" --repo "$TARGET_REPO" || _rc=$?
    fi
    if [ "$_rc" -ne 0 ]; then
        printf '[gh-pr-approve] board sync rc=%s — continuing (soft-fail).\n' "$_rc" >&2
    fi
else                                                                                 # tier 5, soft
    if [ -n "$_sc_was" ]; then export SHELL_COMMON="$_sc_prev"; else unset SHELL_COMMON; fi
    printf '[gh-pr-approve] no usable shell-common at %s — board sync skipped; the verdict itself is unaffected.\n' \
        "$_HELPER" >&2
fi
unset _sc_was _sc_prev
exit 0
