#!/usr/bin/env bash
# tests/bats/fixtures/gh_pr_reply_board_sync.sh
# Runs the shipped gh-pr:reply board step,
#   skills/reply/lib/step6-board-and-labels.sh --phase pre-gate
# against a fake shell-common: _gh_project_status_sync records its argv and
# returns FAKE_HELPER_RC; _gh_pr_drop_label (the review-passed drop that
# follows) is a silent success. No hand copy of the block lives here.
#
# Inputs: FAKE_HELPER_LOG (required), FAKE_HELPER_RC (default 0).

fake_reply_sc() {
    mkdir -p "$1/functions"
    cat >"$1/functions/gh_project_status.sh" <<'SC'
_gh_project_status_sync() {
    printf 'helper called args=%s\n' "$*" >>"$FAKE_HELPER_LOG"
    return "${FAKE_HELPER_RC-0}"
}
SC
    cat >"$1/functions/gh_pr_edit_safe.sh" <<'SC'
_gh_pr_drop_label() { return 0; }
SC
}

# Usage: gh_pr_reply_board_sync_step65 <pr> <pushed-fixes> <owner/repo>
# An empty <pushed-fixes> is the unset case: the script defaults it to 0.
gh_pr_reply_board_sync_step65() {
    local _sc="${TEST_TEMP_HOME:?}/sc"
    [ -f "$_sc/functions/gh_project_status.sh" ] || fake_reply_sc "$_sc"
    FAKE_HELPER_RC="${FAKE_HELPER_RC-0}" SHELL_COMMON="$_sc" TARGET_HOST=github.com TARGET_REPO="${3-}" \
        bash "${REPO_ROOT}/skills/reply/lib/step6-board-and-labels.sh" --phase pre-gate "$1" "${2-}"
}
