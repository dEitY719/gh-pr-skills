#!/usr/bin/env bash
# tests/bats/fixtures/gh_pr_merge_train_close_impl_tab.sh
# Runs the shipped gh-pr:merge-train step-7 impl-tab close: the first ```bash
# fence of skills/merge-train/references/train-loop.md ("Closing the merged
# PR's implementation tab", dEitY719/dotfiles#1565), extracted at test time
# with its `<head>` placeholder filled in. No hand copy of the block lives here.
#
# The herdr lookup SSOT it sources from ${DOTFILES_ROOT:-$HOME/dotfiles} is the
# double in fixtures/herdr_agent_lookup_stub.sh. Test seams: the test's `git` /
# `herdr` shell functions shadow the binaries (the block runs in a subshell of
# the test shell, so no export is needed).
# shellcheck disable=SC2034,SC1091  # vars are read by the eval'd shipped blocks or the .bats; sources resolve at run time

# shellcheck source=fixtures/herdr_agent_lookup_stub.sh
. "${FIXTURES}/herdr_agent_lookup_stub.sh"

close_impl_tab_block() {
    fence_block "${REPO_ROOT}/skills/merge-train/references/train-loop.md" 1
}

# Usage: gh_pr_merge_train_close_impl_tab "$HEAD_REF"
# Always returns 0 — the block runs after the merge succeeded. Pure-bash
# substitution, so the "herdr not installed" test's narrowed PATH still works.
gh_pr_merge_train_close_impl_tab() {
    local _b
    _b=$(close_impl_tab_block)
    (
        DOTFILES_ROOT="${DOTFILES_ROOT:-${TEST_TEMP_HOME}/dotfiles}"
        eval "${_b//<head>/$1}"
    )
    return 0
}
