#!/usr/bin/env bats
# tests/bats/gh_pr_stacked_detect.bats
# Verify the Step 1a stacked-PR auto-detect logic of gh-pr:create, shipped in
#   skills/create/lib/stacked-pr.sh (design: skills/create/references/stacked-pr.md)
# Fixture: fixtures/gh_pr_stacked_detect.sh loads the shipped functions (moved from
# dEitY719/dotfiles tests/bats/skills/ by dEitY719/dotfiles#2200; the hand
# copy is gone).
#
# 10-case compatibility matrix (issue #616 added case 10 for multi-stack):
#   1. dotfiles solo (no stacked signals)        → Stage 1 fail, base=default
#   2. AgentToolbox parent unique                → Stage 1+2, 1 candidate
#   3. AgentToolbox parent ambiguous             → Stage 1+2, 2+ candidates
#   4. AgentToolbox no parent (root issue)       → Stage 1 pass, 0 candidates
#   5. --no-stack override                       → mode=no-stack
#   6. --base <branch> override                  → mode=base
#   7. Mutually-exclusive flags (--no-stack + --base) → rc=2 abort
#   8. --base (missing arg)                      → rc=3 abort
#   9. Auto-detected parent state ≠ OPEN          → rc=5 abort + hint
#  10. Auto-detected parent already stacked       → rc=6 abort + hint

load 'test_helper'

setup() {
    setup_isolated_home
    # shellcheck source=fixtures/gh_pr_stacked_detect.sh
    source "${FIXTURES}/gh_pr_stacked_detect.sh"
    SANDBOX="$(mktemp -d)"
}

teardown() {
    [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ] && rm -rf "$SANDBOX"
    unset FAKE_OPEN_PRS FAKE_ANCESTOR_REFS FAKE_NONDEFAULT_REFS FAKE_PARENT_STATE
    unset FAKE_PARENT_BODY _GH_PR_PARENT_BODY_CACHE
    unset STACK_MODE STACK_BASE ISSUE_NUMBER REMOTE
    teardown_isolated_home
}

# ── 1. Stage 1: solo / no signals ─────────────────────────────────────
@test "stage1: empty repo (no signals) → not stacked (rc=1)" {
    run is_stacked_pr_repo "$SANDBOX"
    [ "$status" -eq 1 ]
}

# ── 2/3/4. Stage 1: each signal is detected ───────────────────────────
@test "stage1: workflow file → stacked" {
    mkdir -p "$SANDBOX/.github/workflows"
    touch    "$SANDBOX/.github/workflows/stacked-closes-rollup.yml"
    run is_stacked_pr_repo "$SANDBOX"
    assert_success
}

@test "stage1: CLAUDE.md keyword → stacked" {
    printf 'see claude-enter-issue for details\n' > "$SANDBOX/CLAUDE.md"
    run is_stacked_pr_repo "$SANDBOX"
    assert_success
}

@test "stage1: AGENTS.md 'Depends on #' → stacked" {
    printf 'use Depends on # in PR bodies\n' > "$SANDBOX/AGENTS.md"
    run is_stacked_pr_repo "$SANDBOX"
    assert_success
}

@test "stage1: agent-toolbox/ dir → stacked" {
    mkdir -p "$SANDBOX/agent-toolbox"
    run is_stacked_pr_repo "$SANDBOX"
    assert_success
}

@test "stage1: .claude/github-integration.md keyword → stacked" {
    mkdir -p "$SANDBOX/.claude"
    printf 'Backlog 중복 검사: stacked PR 정책\n' > "$SANDBOX/.claude/github-integration.md"
    run is_stacked_pr_repo "$SANDBOX"
    assert_success
}

@test "stage1: keyword absent in CLAUDE.md → not stacked" {
    printf 'just a regular project doc\n' > "$SANDBOX/CLAUDE.md"
    run is_stacked_pr_repo "$SANDBOX"
    [ "$status" -eq 1 ]
}

# ── Compatibility matrix #1: dotfiles solo invocation ─────────────────
# parse_stacked_args sets globals; bats `run` would fork a subshell and lose
# them, so we invoke directly. A non-zero rc trips bats's test-body errexit.
@test "matrix-1: dotfiles solo / no flags → mode=auto, no override" {
    parse_stacked_args
    [ "$STACK_MODE" = "auto" ]
    [ -z "$STACK_PARENT" ]
    [ -z "$STACK_BASE" ]
}

# ── Compatibility matrix #2: AgentToolbox parent unique ───────────────
@test "matrix-2: stage2 with single ancestor PR → 1 candidate line" {
    FAKE_OPEN_PRS=$'201 feat/parent-branch\n205 feat/sibling-branch'
    FAKE_ANCESTOR_REFS='origin/feat/parent-branch'
    FAKE_NONDEFAULT_REFS='origin/feat/parent-branch'
    run find_parent_pr_candidates main
    assert_success
    assert_output --partial '201:feat/parent-branch'
    refute_output --partial '205:'
}

# ── Compatibility matrix #3: AgentToolbox parent ambiguous ────────────
@test "matrix-3: stage2 with two ancestor PRs → 2 candidate lines" {
    FAKE_OPEN_PRS=$'201 feat/parent-a\n205 feat/parent-b\n300 feat/orphan'
    FAKE_ANCESTOR_REFS='origin/feat/parent-a origin/feat/parent-b'
    FAKE_NONDEFAULT_REFS='origin/feat/parent-a origin/feat/parent-b'
    run find_parent_pr_candidates main
    assert_success
    assert_output --partial '201:feat/parent-a'
    assert_output --partial '205:feat/parent-b'
    refute_output --partial '300:'
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
}

# ── Compatibility matrix #4: AgentToolbox no parent ───────────────────
@test "matrix-4: stage2 with zero ancestor PRs → empty output" {
    FAKE_OPEN_PRS=$'201 feat/unrelated-a\n205 feat/unrelated-b'
    FAKE_ANCESTOR_REFS=''
    FAKE_NONDEFAULT_REFS=''
    run find_parent_pr_candidates main
    assert_success
    [ -z "$output" ]
}

# ── [remote] threading (#1405) ────────────────────────────────────────
# find_parent_pr_candidates probes refs on $REMOTE, defaulting to origin, so
# the matrix cases above (which set origin/* refs and never set REMOTE) are
# unchanged.
@test "remote: unset REMOTE keeps the origin/* ref probes (regression zero)" {
    FAKE_OPEN_PRS='201 feat/parent-branch'
    FAKE_ANCESTOR_REFS='origin/feat/parent-branch'
    FAKE_NONDEFAULT_REFS='origin/feat/parent-branch'
    run find_parent_pr_candidates main
    assert_success
    assert_output --partial '201:feat/parent-branch'
}

@test "remote: REMOTE=upstream probes upstream/* refs, not origin/*" {
    REMOTE=upstream
    FAKE_OPEN_PRS='201 feat/parent-branch'
    FAKE_ANCESTOR_REFS='upstream/feat/parent-branch'
    FAKE_NONDEFAULT_REFS='upstream/feat/parent-branch'
    run find_parent_pr_candidates main
    assert_success
    assert_output --partial '201:feat/parent-branch'
}

@test "remote: REMOTE=upstream ignores origin/* ancestor refs" {
    REMOTE=upstream
    FAKE_OPEN_PRS='201 feat/parent-branch'
    FAKE_ANCESTOR_REFS='origin/feat/parent-branch'
    FAKE_NONDEFAULT_REFS='origin/feat/parent-branch'
    run find_parent_pr_candidates main
    assert_success
    [ -z "$output" ]
}

@test "matrix-4b: stage2 candidate with same merge-base as default → dropped" {
    # PR head is an ancestor of HEAD but its merge-base equals the default's
    # — i.e. it doesn't actually advance the parent search. Must be skipped.
    FAKE_OPEN_PRS='201 feat/same-as-default'
    FAKE_ANCESTOR_REFS='origin/feat/same-as-default'
    FAKE_NONDEFAULT_REFS=''
    run find_parent_pr_candidates main
    assert_success
    [ -z "$output" ]
}

# ── Compatibility matrix #5: --no-stack ───────────────────────────────
@test "matrix-5: --no-stack → STACK_MODE=no-stack" {
    parse_stacked_args --no-stack
    [ "$STACK_MODE" = "no-stack" ]
}

# ── Compatibility matrix #6: --base <branch> ──────────────────────────
@test "matrix-6: --base release/v2.0 → STACK_MODE=base, STACK_BASE=release/v2.0" {
    parse_stacked_args --base release/v2.0
    [ "$STACK_MODE" = "base" ]
    [ "$STACK_BASE" = "release/v2.0" ]
}

# ── Compatibility matrix #7: mutually-exclusive flags ─────────────────
@test "matrix-7: --no-stack --base main → rc=2 with explanatory message" {
    run parse_stacked_args --no-stack --base main
    [ "$status" -eq 2 ]
    assert_output --partial 'mutually exclusive'
}

# ── Compatibility matrix #8: --base missing branch arg ────────────────
@test "matrix-8: --base (no arg) → rc=3 with explanatory message" {
    run parse_stacked_args --base
    [ "$status" -eq 3 ]
    assert_output --partial 'requires a branch name'
}

# ── Compatibility matrix #9: parent state guard (F-4) ─────────────────
@test "matrix-9: parent state OPEN → assert_parent_pr_open succeeds silently" {
    FAKE_PARENT_STATE=OPEN
    run assert_parent_pr_open 201
    assert_success
    [ -z "$output" ]
}

@test "matrix-9: parent state CLOSED → rc=5 with recovery hint on stderr" {
    FAKE_PARENT_STATE=CLOSED
    run assert_parent_pr_open 201
    [ "$status" -eq 5 ]
    assert_output --partial 'parent PR #201 state=CLOSED'
    assert_output --partial 'stacking requires OPEN parent'
    assert_output --partial '--no-stack'
}

@test "matrix-9: parent state MERGED → rc=5 with recovery hint" {
    FAKE_PARENT_STATE=MERGED
    run assert_parent_pr_open 201
    [ "$status" -eq 5 ]
    assert_output --partial 'state=MERGED'
}

# ── Compatibility matrix #10: multi-stack guard (F-6, issue #616) ─────
@test "matrix-10: parent body without Depends → assert_parent_pr_not_stacked succeeds" {
    FAKE_PARENT_BODY='## Summary
Normal single-stack PR body. No Depends trailer here.'
    run assert_parent_pr_not_stacked 201
    assert_success
    [ -z "$output" ]
}

@test "matrix-10: parent body empty → assert_parent_pr_not_stacked succeeds" {
    FAKE_PARENT_BODY=''
    run assert_parent_pr_not_stacked 201
    assert_success
}

@test "matrix-10: parent body with 'Depends on #100' → rc=6 with recovery hint" {
    FAKE_PARENT_BODY='## Summary
Adds widget X.

## Related
Depends on #100'
    run assert_parent_pr_not_stacked 201
    [ "$status" -eq 6 ]
    assert_output --partial 'parent PR #201 is already stacked'
    assert_output --partial 'multi-stack not supported'
    assert_output --partial '--no-stack'
    assert_output --partial '--base'
}

@test "matrix-10: parent body with lowercase 'depends on #N' → rc=6 (case-insensitive)" {
    FAKE_PARENT_BODY='depends on #42'
    run assert_parent_pr_not_stacked 201
    [ "$status" -eq 6 ]
}

@test "matrix-10: parent body with leading whitespace before Depends → rc=6" {
    FAKE_PARENT_BODY='   Depends on #77'
    run assert_parent_pr_not_stacked 201
    [ "$status" -eq 6 ]
}

@test "matrix-10: 'Depends on' as inline prose (not line-start) → rc=0 (no false positive)" {
    FAKE_PARENT_BODY='This change Depends on #100 indirectly but is not stacked.'
    run assert_parent_pr_not_stacked 201
    assert_success
}

@test "matrix-10: body cache from assert_parent_pr_open reused (zero extra API)" {
    # Simulate the dispatcher path: state-helper populates the cache, then
    # the body-guard reads it without a second fetch. We assert this by
    # leaving FAKE_PARENT_BODY unset — only the cache should carry it.
    _GH_PR_PARENT_BODY_CACHE='Depends on #999'
    run assert_parent_pr_not_stacked 201
    [ "$status" -eq 6 ]
    assert_output --partial '#201 is already stacked'
}

# ── Legacy positional issue arg still parsed ──────────────────────────
@test "parse: positional integer arg → ISSUE_NUMBER (legacy /gh-pr 123)" {
    parse_stacked_args 123
    [ "$STACK_MODE" = "auto" ]
    [ "$ISSUE_NUMBER" = "123" ]
}

@test "parse: positional integer + --no-stack → both bound" {
    parse_stacked_args 42 --no-stack
    [ "$STACK_MODE" = "no-stack" ]
    [ "$ISSUE_NUMBER" = "42" ]
}
