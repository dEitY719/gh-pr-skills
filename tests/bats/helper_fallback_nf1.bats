#!/usr/bin/env bats
# tests/bats/helper_fallback_nf1.bats
# Smoke test for dEitY719/dotfiles#644 — helper-fallback NF-1, on the shipped
# soft loader in skills/approve/lib/board-approved-sync.sh (fixture:
# fixtures/helper_fallback_nf1.sh). Moved from dEitY719/dotfiles
# tests/bats/skills/ by dEitY719/dotfiles#2200.
#
# Acceptance criteria mapped from dEitY719/dotfiles#644:
#   - SHELL_COMMON pointing at an empty dir -> no `command not found`, the
#     board step is skipped, the calling skill continues.
#   - SHELL_COMMON pointing at a populated dir -> helper sourced,
#     _gh_project_status_sync invoked.
# Since harness-skills#60 the skip is no longer silent: it is ONE warning that
# names the path it tried, so a broken install is visible.

load 'test_helper'

setup() {
    setup_isolated_home
    # shellcheck source=fixtures/helper_fallback_nf1.sh
    source "${FIXTURES}/helper_fallback_nf1.sh"
}

teardown() {
    teardown_isolated_home
    unset SHELL_COMMON
}

@test "helper present → block runs sync and continues" {
    local helper_dir="$TEST_TEMP_HOME/sc/lib"
    nf1_install_fake_helper "$helper_dir/gh_project_status.sh"
    export SHELL_COMMON="$TEST_TEMP_HOME/sc"

    run nf1_canonical_block 644
    assert_success
    assert_output --partial "BLOCK_RAN sync_called"
    assert_output --partial "BLOCK_COMPLETED"
}

@test "helper missing (SHELL_COMMON=/tmp/empty equivalent) → one warning, no command-not-found" {
    # NF-1 core guarantee from issue #644: skill body keeps running.
    export SHELL_COMMON="$TEST_TEMP_HOME/empty-sc"
    [ ! -e "$SHELL_COMMON/lib/gh_project_status.sh" ] || {
        echo "precondition violated: fake SHELL_COMMON should not contain helper" >&2
        return 1
    }

    run nf1_canonical_block 644
    assert_success
    refute_output --partial "BLOCK_RAN sync_called"
    refute_output --partial "command not found"
    refute_output --partial "_gh_project_status_sync"
    assert_output --partial "no usable shell-common at ${SHELL_COMMON}/lib/gh_project_status.sh"
    assert_output --partial "BLOCK_COMPLETED"
}

@test "helper missing, SHELL_COMMON unset → fallback path also skips with one warning" {
    # When SHELL_COMMON is unset the canonical block falls back to
    # $HOME/dotfiles/shell-common. Under bats isolation HOME is a fresh
    # tmpdir and CLAUDE_PLUGIN_ROOT is unset, so no tier resolves.
    unset SHELL_COMMON

    run nf1_canonical_block 644
    assert_success
    refute_output --partial "BLOCK_RAN sync_called"
    refute_output --partial "command not found"
    assert_output --partial "no usable shell-common at ${HOME}/dotfiles/shell-common/lib/gh_project_status.sh"
    assert_output --partial "BLOCK_COMPLETED"
}

@test "the loader's helper contract matches the vendored helper (drift guard)" {
    # The loader names the helper path and proves the function it needs; the
    # vendored copy (tier 2) must still define that function.
    local lib="${REPO_ROOT}/skills/approve/lib/board-approved-sync.sh"
    local helper="${REPO_ROOT}/lib/vendor/shell-common/lib/gh_project_status.sh"
    run grep -F '/lib/gh_project_status.sh" # tier 1' "$lib"
    assert_success
    run grep -F '[ "$(command -v _gh_project_status_sync 2>/dev/null)" = _gh_project_status_sync ]' "$lib"
    assert_success
    run grep -E '^_gh_project_status_sync\(\) \{' "$helper"
    assert_success
}
