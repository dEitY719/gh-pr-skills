#!/usr/bin/env bash
# tests/bats/fixtures/gh_pr_approve_board_sync.sh
# Runs the shipped gh-pr:approve Step 4.5 script,
#   skills/approve/lib/board-approved-sync.sh
# against a fake shell-common whose _gh_project_status_sync records the bypass
# binding it saw plus its full argv. No hand copy of the block lives here.
#
# Inputs: FAKE_HELPER_LOG (required), FAKE_HELPER_RC (default 0).

# Usage: fake_board_sc <dir> — writes <dir>/lib/gh_project_status.sh.
# The file also records the bypass value seen at LOAD time, so a test can tell
# a per-call prefix binding from a global export.
fake_board_sc() {
    mkdir -p "$1/lib"
    cat >"$1/lib/gh_project_status.sh" <<'SC'
printf 'helper loaded bypass=%s\n' "${_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS-unset}" >>"$FAKE_HELPER_LOG"
_gh_project_status_sync() {
    printf 'helper called bypass=%s args=%s\n' \
        "${_GH_PROJECT_STATUS_GUARD_APPROVED_BYPASS-unset}" "$*" >>"$FAKE_HELPER_LOG"
    return "${FAKE_HELPER_RC-0}"
}
SC
}

# Usage: gh_pr_approve_board_sync_step45 <pr> <bypass 0|1> <owner/repo>
# Same call shape as the old mirror; runs the real script in a child bash.
gh_pr_approve_board_sync_step45() {
    local _sc="${TEST_TEMP_HOME:?}/sc" _flag=
    [ -f "$_sc/lib/gh_project_status.sh" ] || fake_board_sc "$_sc"
    [ "${2-0}" = 1 ] && _flag=--self-record
    # shellcheck disable=SC2086  # an empty flag must vanish
    FAKE_HELPER_RC="${FAKE_HELPER_RC-0}" SHELL_COMMON="$_sc" TARGET_HOST=github.com TARGET_REPO="${3-}" \
        bash "${REPO_ROOT}/skills/approve/lib/board-approved-sync.sh" "$1" $_flag
}
