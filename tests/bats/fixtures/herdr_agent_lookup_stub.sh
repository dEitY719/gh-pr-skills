#!/usr/bin/env bash
# tests/bats/fixtures/herdr_agent_lookup_stub.sh
# Test double for dEitY719/dotfiles shell-common/lib/herdr_agent_lookup.sh,
# the herdr "which agent sits on this worktree?" SSOT (dEitY719/dotfiles#1569)
# that skills/merge/lib/post-merge-housekeeping.sh step 2 and
# skills/merge-train/references/train-loop.md step 7 source from
# ${DOTFILES_ROOT:-$HOME/dotfiles}. It is not vendored here, so the moved
# suites put this double at that path instead.
#
# Same call contract and return codes (0 match / 1 herdr not askable /
# 3 nothing there), deliberately NARROWER predicate: exact `cwd` or
# `foreground_cwd` equality, first match, optional status filter. The
# boundary / subdirectory / prefix-sibling rules are the SSOT's own and are
# tested where it lives: dEitY719/dotfiles tests/bats/functions/herdr_agent_lookup.bats.

herdr_agent_physical_path() {
    (cd -P "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"
}

herdr_agent_match_for_cwd() {
    [ -n "${1-}" ] || return 3
    _stub_json=$(herdr agent list 2>/dev/null) && [ -n "$_stub_json" ] || return 1
    _stub_row=$(printf '%s' "$_stub_json" | jq -r --arg p "$1" --arg s "${2-}" '
        [ .result.agents[]? | select(.cwd == $p or .foreground_cwd == $p) ]
        | first | select(. != null)
        | select($s == "" or (.agent_status // "") == $s)
        | [ (.tab_id // ""), (.agent_status // ""), (.workspace_id // "") ] | @tsv
    ' 2>/dev/null) || return 1
    [ -n "$_stub_row" ] || return 3
    printf '%s' "$_stub_row"
}

herdr_agent_tab_for_cwd() {
    _stub_m=$(herdr_agent_match_for_cwd "$@") || return
    _stub_t=${_stub_m%%"	"*}
    [ -n "$_stub_t" ] || return 3
    printf '%s' "$_stub_t"
}

# Usage: install_herdr_lookup_stub <dotfiles-root> — puts this double where
# the shipped code looks for the SSOT.
install_herdr_lookup_stub() {
    mkdir -p "$1/shell-common/lib"
    ln -sf "${FIXTURES}/herdr_agent_lookup_stub.sh" "$1/shell-common/lib/herdr_agent_lookup.sh"
}
