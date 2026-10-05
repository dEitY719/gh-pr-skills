#!/usr/bin/env bash
# gh-pr:create Step 4.5 — pre-push lint guard (HARD).
#
#   bash skills/create/lib/lint-guard.sh <BASE_BRANCH>
#
# Sources shell-common's gh_pr_lint.sh and runs `_gh_pr_lint_run <base>` on the
# PR's changed files. It auto-skips (exit 0) on GH_PR_LINT_BYPASS=1, an empty
# change set, or no applicable tool.
# exit: 0 clean or skipped | 1 lint failed (stop BEFORE the Step 5 push), or no
#       usable shell-common (tier 5 — a broken install, never a silent pass).
# Detection priority, bypass and skip matrix: references/lint-guard.md.
# Guard: tests/create-lib.sh.

BASE_BRANCH="${1-}"
[ -n "$BASE_BRANCH" ] || { printf 'usage: lint-guard.sh <BASE_BRANCH>\n' >&2; exit 1; }
_SC="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common"                                  # tier 1
if [ ! -f "$_SC/functions/gh_pr_lint.sh" ]; then
    [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || {                                            # tier 5
        printf '[gh-pr:create] no shell-common under %s, and CLAUDE_PLUGIN_ROOT is unset. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
            "$_SC" >&2
        exit 1
    }
    _SC="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common"                                # tier 2
fi
unset -f _gh_pr_lint_run 2>/dev/null || :
unalias _gh_pr_lint_run 2>/dev/null || :
export SHELL_COMMON="$_SC"                                                           # before the load
# shellcheck disable=SC1091  # resolved at run time by the tier ladder above
[ -f "$_SC/functions/gh_pr_lint.sh" ] && . "$_SC/functions/gh_pr_lint.sh"
[ "$(command -v _gh_pr_lint_run 2>/dev/null)" = _gh_pr_lint_run ] || {               # tier 5
    unset SHELL_COMMON
    printf '[gh-pr:create] %s did not load a usable shell-common. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    exit 1
}
_gh_pr_lint_run "$BASE_BRANCH" || {
    printf 'gh-pr:create stopped at Step 4.5 (lint guard).\n' >&2
    exit 1
}
