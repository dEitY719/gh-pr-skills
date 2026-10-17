#!/usr/bin/env bash
# tests/bats/fixtures/gh_pr_merge_review_passed_cleanup.sh
# Runs the shipped gh-pr:merge Step 4 script,
#   skills/merge/lib/post-merge-housekeeping.sh
# whose step 3 drops `review-passed` through the vendored shared primitive
# lib/vendor/shell-common/lib/gh_pr_edit_safe.sh (_gh_pr_drop_label).
# Steps 1, 2 and 4 are switched off so only step 3 speaks: the board helper is
# a no-op stub, the herdr lookup is unreadable, GH_DISABLE_AI_METRICS=1.
#
# The test's `gh` shell function is exported into the child bash.

merge_cleanup_sc() {
    local _sc="${TEST_TEMP_HOME:?}/sc" _v="${REPO_ROOT}/lib/vendor/shell-common/lib"
    if [ ! -d "$_sc/lib" ]; then
        mkdir -p "$_sc/lib"
        printf '%s\n' '_gh_project_status_sync() { :; }' \
            '_gh_pr_closing_issue_numbers() { :; }' >"$_sc/lib/gh_project_status.sh"
        ln -s "$_v/gh_pr_edit_safe.sh" "$_sc/lib/gh_pr_edit_safe.sh"
        ln -s "$_v/dotfiles_root.sh" "$_sc/lib/dotfiles_root.sh"
    fi
    printf '%s' "$_sc"
}

# Usage: merge_step4_then_report <pr> <repo> <host>
# Step 4 then the Step 5 report line. The report prints only when Step 4
# exits 0 — and Step 4's contract is that it always does.
merge_step4_then_report() {
    local _sc
    _sc=$(merge_cleanup_sc)
    export -f gh
    SHELL_COMMON="$_sc" DOTFILES_ROOT="${TEST_TEMP_HOME}/no-dotfiles" GH_DISABLE_AI_METRICS=1 \
        TARGET_HOST="$3" bash "${REPO_ROOT}/skills/merge/lib/post-merge-housekeeping.sh" "$1" "$2" "" &&
        printf '[OK] PR #%s merged\n' "$1"
}
