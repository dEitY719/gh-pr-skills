#!/usr/bin/env bash
# tests/bats/fixtures/gh_pr_merge_herdr_notify.sh
# Runs the shipped gh-pr:merge Step 4 herdr idle-tab hint — step 2 of
#   skills/merge/lib/post-merge-housekeeping.sh
# (spec: skills/merge/references/herdr-tab-notify.sh.md). Steps 1, 3 and 4 are
# silenced so only the hint speaks: no-op board/label stubs, and
# GH_DISABLE_AI_METRICS=1. The herdr lookup SSOT is the double in
# fixtures/herdr_agent_lookup_stub.sh, installed under $DOTFILES_ROOT.
#
# Test seams: the test's `git` / `herdr` shell functions are exported into the
# child bash, so they shadow the binaries exactly as before.
# shellcheck disable=SC2034,SC1091  # vars are read by the eval'd shipped blocks or the .bats; sources resolve at run time

# shellcheck source=fixtures/herdr_agent_lookup_stub.sh
. "${FIXTURES}/herdr_agent_lookup_stub.sh"

# Builds the silenced shell-common and the lookup double. Call from setup():
# one test narrows PATH to a dir without mkdir/ln before it runs the hint.
herdr_notify_setup() {
    local _sc="${TEST_TEMP_HOME:?}/sc"
    mkdir -p "$_sc/lib"
    printf '%s\n' '_gh_project_status_sync() { :; }' \
        '_gh_pr_closing_issue_numbers() { :; }' >"$_sc/lib/gh_project_status.sh"
    printf '%s\n' '_gh_pr_edit_safe_label() { :; }' \
        '_gh_pr_drop_label() { :; }' >"$_sc/lib/gh_pr_edit_safe.sh"
    install_herdr_lookup_stub "${TEST_TEMP_HOME}/dotfiles"
}

# Usage: gh_pr_merge_herdr_notify "$HEAD_REF"
gh_pr_merge_herdr_notify() {
    local _sc="${TEST_TEMP_HOME:?}/sc"
    export FAKE_WORKTREE_LIST FAKE_AGENT_JSON FAKE_WORKSPACE_JSON FAKE_AGENT_RC FAKE_CALL_LOG
    declare -F git >/dev/null && export -f git
    declare -F herdr >/dev/null && export -f herdr
    SHELL_COMMON="$_sc" DOTFILES_ROOT="${DOTFILES_ROOT:-${TEST_TEMP_HOME}/dotfiles}" \
        GH_DISABLE_AI_METRICS=1 TARGET_HOST=github.com \
        "$BASH" "${REPO_ROOT}/skills/merge/lib/post-merge-housekeeping.sh" 42 o/r "$1"
}

# The shipped step-2 text, for the static NF-2 guards.
herdr_notify_block() {
    sed -n '/^# --- 2\. herdr idle-tab hint/,/^# --- 3\./p' \
        "${REPO_ROOT}/skills/merge/lib/post-merge-housekeeping.sh"
}
