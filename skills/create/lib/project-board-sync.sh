#!/usr/bin/env bash
# gh-pr:create Step 7 — PR card -> `In review`, linked Issue cards -> `In progress`.
#
#   GH_HOST=<host> GH_REPO=<owner/repo> REMOTE=<remote> \
#       bash skills/create/lib/project-board-sync.sh <PR_NUMBER>
#
# Skips inline (one stderr line) when a PostToolUse hook already owns the sync
# (dEitY719/dotfiles#390). Otherwise loads gh_project_status.sh through the SOFT
# warn-and-skip loader (harness-skills#60) and syncs; every sync is `|| true`.
# GH_REPO, when empty, is re-resolved from $REMOTE's URL — never from
# `gh repo view` (dEitY719/dotfiles#1403) — through a HARD gh_host.sh loader.
# exit: 0 synced / skipped / no board | 1 only that nested gh_host.sh loader
#       hit tier 5 (a broken install). Step 7 emits its marker either way.
# Report-row mapping and rationale: references/project-board-sync.md.
# Guards: tests/create-lib.sh, tests/plugin-root-tier5.sh §5.

PR_NUMBER="${1-}"
case "$PR_NUMBER" in
    '' | *[!0-9]*) printf '[gh-pr] board sync: PR_NUMBER %s is not a number — skipped; the PR itself is unaffected.\n' "'$PR_NUMBER'" >&2; exit 0 ;;
esac

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
    # Soft warn-and-skip loader (harness-skills#60). A missing helper, or one
    # that sources but defines nothing (interactive-guard regression, partial
    # sourcing, a rename), skips the board sync with ONE warning naming the
    # path — no longer silently (dEitY719/dotfiles#644 NF-1's silence hid a
    # broken install). `|| true` alone would absorb `command not found`
    # (rc 127) and the whole reconciliation would no-op — dEitY719/dotfiles#724.
    _HELPER="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/gh_project_status.sh" # tier 1
    [ -f "$_HELPER" ] || [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] \
        || _HELPER="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common/functions/gh_project_status.sh" # tier 2
    _sc_was=${SHELL_COMMON+set} _sc_prev="${SHELL_COMMON-}"                      # save
    unset -f _gh_project_status_sync 2>/dev/null || :
    unalias _gh_project_status_sync 2>/dev/null || :
    export SHELL_COMMON="${_HELPER%/functions/gh_project_status.sh}"             # before the load
    # shellcheck disable=SC1090  # resolved at run time by the tier ladder above
    [ -r "$_HELPER" ] && . "$_HELPER"
    if [ "$(command -v _gh_project_status_sync 2>/dev/null)" = _gh_project_status_sync ]; then
        # Auto-resolve GH_REPO when unset/empty so neither the PR sync
        # below nor the linked-issues loop is left to the helper's
        # `gh repo view` auto-detect (PR dEitY719/dotfiles#780 review, dEitY719/dotfiles#1405).
        if [ -z "${GH_REPO:-}" ]; then
            # Re-resolve from git's remote, never from `gh repo view`
            # (which answers gh CLI's default repo — wrong host on a
            # dual-host login, dEitY719/dotfiles#1403). The remote is parameterized: it is
            # $REMOTE, the [remote] positional bound in Step 1a-0, `origin`
            # by default (dEitY719/dotfiles#1405). Source gh_host.sh explicitly:
            # gh_project_status.sh only sources it on the GH_HOST-unset
            # path, which Step 1a-0's export already bypassed.
            _SC="${SHELL_COMMON:-$HOME/dotfiles/shell-common}"                   # tier 1
            if [ ! -f "$_SC/functions/gh_host.sh" ]; then
                [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || {                            # tier 5
                    printf '[gh-pr:create] no shell-common under %s, and CLAUDE_PLUGIN_ROOT is unset. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
                        "$_SC" >&2
                    exit 1
                }
                _SC="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common"                # tier 2
            fi
            unset -f _gh_resolve_host 2>/dev/null || :
            unalias _gh_resolve_host 2>/dev/null || :
            export SHELL_COMMON="$_SC"                                           # before the load
            # shellcheck disable=SC1091  # resolved at run time by the tier ladder above
            [ -f "$_SC/functions/gh_host.sh" ] && . "$_SC/functions/gh_host.sh"
            [ "$(command -v _gh_resolve_host 2>/dev/null)" = _gh_resolve_host ] || { # tier 5
                unset SHELL_COMMON
                printf '[gh-pr:create] %s did not load a usable shell-common. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
                    "$_SC" >&2
                exit 1
            }
            GH_REPO=$(_gh_parse_owner_repo_url "$(git remote get-url "${REMOTE:-origin}")" 2>/dev/null || true)
        fi
        _gh_project_status_sync pr "$PR_NUMBER" "In review" --repo "$GH_REPO" || true
        for _issue in $(_gh_pr_closing_issue_numbers "$PR_NUMBER" "$GH_REPO" 2>/dev/null || true); do
            _gh_project_status_sync issue "$_issue" "In progress" \
                --only-from "Backlog,Ready,In review" || true
        done
    else                                                                         # tier 5, soft
        if [ -n "$_sc_was" ]; then export SHELL_COMMON="$_sc_prev"; else unset SHELL_COMMON; fi
        printf '[gh-pr] no usable shell-common at %s — board sync skipped; the PR itself is unaffected.\n' \
            "$_HELPER" >&2
    fi
    unset _sc_was _sc_prev
fi
