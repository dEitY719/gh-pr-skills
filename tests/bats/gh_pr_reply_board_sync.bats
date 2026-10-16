#!/usr/bin/env bats
# tests/bats/gh_pr_reply_board_sync.bats
# Verify gh-pr:reply's board sync (`In review` 복귀) gate.
# Runs the shipped skills/reply/lib/step6-board-and-labels.sh --phase pre-gate
# through fixtures/gh_pr_reply_board_sync.sh (moved from dEitY719/dotfiles
# tests/bats/skills/ by dEitY719/dotfiles#2200; the hand-copied block is gone).
#
# Cases drawn from dEitY719/dotfiles#627's acceptance criteria:
#   1. push happened (PUSHED_FIXES > 0)            -> helper called + audit OK line
#   2. no push (PUSHED_FIXES == 0)                 -> no board call, one [OK] no-op line
#   3. PUSHED_FIXES unset                          -> same (default 0)
#   4. helper returns 2 (already In review etc.)   -> WARN line, rc=0 (soft-fail)
#   5. argv carries --only-from "In progress,Changes requested" guard

load 'test_helper'

setup() {
    setup_isolated_home
    FAKE_HELPER_LOG="$(mktemp)"
    export FAKE_HELPER_LOG
    # shellcheck source=fixtures/gh_pr_reply_board_sync.sh
    source "${FIXTURES}/gh_pr_reply_board_sync.sh"
}

teardown() {
    teardown_isolated_home
    [ -n "$FAKE_HELPER_LOG" ] && rm -f "$FAKE_HELPER_LOG"
    unset FAKE_HELPER_LOG FAKE_HELPER_RC
}

@test "board-sync: PUSHED_FIXES>0 → helper called, OK line" {
    run gh_pr_reply_board_sync_step65 663 2 owner/repo
    assert_success
    assert_output --partial 'In review'
    assert_output --partial '[OK] PR'
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial 'helper called'
    assert_output --partial 'args=pr 663 In review --only-from In progress,Changes requested --repo owner/repo'
}

@test "board-sync: PUSHED_FIXES=0 → no board call, [OK] no-op line" {
    run gh_pr_reply_board_sync_step65 663 0 owner/repo
    assert_success
    refute_output --partial '[OK] PR'
    assert_output --partial '수정 커밋 push 없음'
    refute_output --partial '[WARN]'
    run cat "$FAKE_HELPER_LOG"
    refute_output --partial 'helper called'
}

@test "board-sync: PUSHED_FIXES unset → no board call, [OK] no-op line (default 0)" {
    run gh_pr_reply_board_sync_step65 663 "" owner/repo
    assert_success
    refute_output --partial '[OK] PR'
    assert_output --partial '수정 커밋 push 없음'
    refute_output --partial '[WARN]'
    run cat "$FAKE_HELPER_LOG"
    refute_output --partial 'helper called'
}

@test "board-sync: helper rc=2 → WARN line, rc=0 (soft-fail)" {
    FAKE_HELPER_RC=2
    run gh_pr_reply_board_sync_step65 663 1 owner/repo
    assert_success
    assert_output --partial '[WARN] 보드 sync 실패'
    refute_output --partial '[OK] PR'
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial 'helper called'
}

@test "board-sync (#1405): argv carries the explicit --repo" {
    # Without --repo the helper resolves the repo through `gh repo view`,
    # which answers `gh repo set-default` rather than the remote Step 1
    # resolved — the wrong board on a multi-repo host.
    run gh_pr_reply_board_sync_step65 663 5 owner/repo
    assert_success
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial '--repo owner/repo'
}

@test "board-sync: argv carries --only-from guard (regression: don't demote cards already past In review)" {
    # The `--only-from "In progress,Changes requested"` filter is the
    # safety belt that prevents accidentally demoting cards already at
    # `In review` / `Approved` / `Done`. Drop it and a re-run after
    # approval would push the card backwards.
    run gh_pr_reply_board_sync_step65 663 5 owner/repo
    assert_success
    run cat "$FAKE_HELPER_LOG"
    assert_output --partial '--only-from In progress,Changes requested'
}
