#!/bin/sh
# gh-pr:create Step 1a-0 — bind the GitHub target from one remote URL
# (dEitY719/dotfiles#1403, dEitY719/dotfiles#1405).
#
#   _gt=$(sh skills/create/lib/github-target.sh [remote]) || exit 1; eval "$_gt"
#
# stdout: ONE line of shell for the caller to eval —
#   export SHELL_COMMON=… GH_HOST=… GH_REPO=… TARGET_HOST=… REMOTE=…
#   (every value single-quoted). Nothing else is ever written to stdout.
# stderr: the tier-5 / unknown-remote diagnostics.
# exit:   0 bound | 1 no usable shell-common, or unknown remote (stdout empty,
#         so a failed run can never leave a half-bound target behind).
#
# Loader: the HARD tier ladder of harness-skills references/plugin-root.md —
# tier 1 $DOTFILES_ROOT (default $HOME/dotfiles), tier 2 guarded
# $CLAUDE_PLUGIN_ROOT/lib/vendor, no cwd tier, tier 5 stops loudly.
# Contract + rationale: references/github-target.md. Guard: tests/create-lib.sh.

REMOTE="${1:-origin}"
_SC="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common"                                  # tier 1
if [ ! -f "$_SC/functions/gh_host.sh" ]; then
    [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || {                                            # tier 5
        printf '[gh-pr:create] no shell-common under %s, and CLAUDE_PLUGIN_ROOT is unset. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
            "$_SC" >&2
        exit 1
    }
    _SC="$CLAUDE_PLUGIN_ROOT/lib/vendor/shell-common"                                # tier 2
fi
unset -f _gh_resolve_host 2>/dev/null || :
unalias _gh_resolve_host 2>/dev/null || :
export SHELL_COMMON="$_SC"                                                           # before the load
# shellcheck disable=SC1091  # resolved at run time by the tier ladder above
[ -f "$_SC/functions/gh_host.sh" ] && . "$_SC/functions/gh_host.sh"
[ "$(command -v _gh_resolve_host 2>/dev/null)" = _gh_resolve_host ] || {             # tier 5
    unset SHELL_COMMON
    printf '[gh-pr:create] %s did not load a usable shell-common. On Claude Code this is a broken install; on any other harness export CLAUDE_PLUGIN_ROOT=<plugin dir> first.\n' \
        "$_SC" >&2
    exit 1
}
# Never a silent `origin` fallback: $REMOTE also drives every git plumbing
# call in this skill (fetch, ranges, push -u).
REMOTE_URL=$(git remote get-url "$REMOTE" 2>/dev/null) || {
    printf "Error: remote '%s' not found. Available remotes:\n" "$REMOTE" >&2
    git remote -v >&2
    exit 1
}
GH_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL")
TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)

_q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
printf 'export SHELL_COMMON=%s GH_HOST=%s GH_REPO=%s TARGET_HOST=%s REMOTE=%s\n' \
    "$(_q "$SHELL_COMMON")" "$(_q "$TARGET_HOST")" "$(_q "$GH_REPO")" \
    "$(_q "$TARGET_HOST")" "$(_q "$REMOTE")"
