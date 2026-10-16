#!/usr/bin/env bats
# tests/bats/gh_pr_push_policy.bats
# Verify the Step 1b branch-state logic of gh-pr:create, shipped in
#   skills/create/lib/branch-state.sh (rationale: skills/create/references/branch-state.md,
#   push table: skills/create/references/push-and-create.md)
# Fixture: fixtures/gh_pr_push_policy.sh loads the shipped functions (moved from
# dEitY719/dotfiles tests/bats/skills/ by dEitY719/dotfiles#2200; the hand
# copy is gone).
#
# dEitY719/dotfiles#1315 verification checklist:
#   F-1-1  no upstream                        → push -u origin HEAD
#   F-1-2  upstream == origin/<current>       → bare push
#   F-1-3  upstream == origin/main, on feature → push -u origin HEAD (NOT bare)
#   F-1-4  upstream diverged                  → STOP (pre-existing row)
#   F-2-1  on base + local-only commits       → auto-branch + rewind
#   F-2-2  on base + commits already on origin → nothing-to-pr (stop)
#   F-2-3  Korean commit titles               → ASCII-safe branch names
#
# dEitY719/dotfiles#1405 verification checklist ([remote] threading):
#   F-3-1  remote argument omitted             → identical to pre-#1405 output
#   F-3-2  remote=upstream, no upstream ref    → push -u upstream HEAD
#   F-3-3  remote=upstream, upstream/<branch>  → paired (not a mispair)
#   F-3-4  remote=upstream, origin/<branch>    → mispair → push -u upstream HEAD
#   F-3-5  diverged                            → STOP regardless of remote

load 'test_helper'

setup() {
    setup_isolated_home
    # shellcheck source=fixtures/gh_pr_push_policy.sh
    source "${FIXTURES}/gh_pr_push_policy.sh"
}

teardown() {
    teardown_isolated_home
}

# ── F-1-0: upstream ref normalisation ─────────────────────────────────
@test "normalize: refs/remotes/origin/main → origin/main" {
    run gh_pr_normalize_upstream 'refs/remotes/origin/main'
    assert_success
    assert_output 'origin/main'
}

@test "normalize: already-abbreviated origin/main passes through" {
    run gh_pr_normalize_upstream 'origin/main'
    assert_success
    assert_output 'origin/main'
}

@test "normalize: empty upstream stays empty" {
    run gh_pr_normalize_upstream ''
    assert_success
    [ -z "$output" ]
}

# ── F-1-1: no upstream ────────────────────────────────────────────────
@test "F-1-1: no upstream → push -u origin HEAD" {
    run gh_pr_push_action 'feat/issue-1315' '' ''
    assert_success
    assert_output 'push -u origin HEAD'
}

@test "F-1-1: no upstream is NOT reported as a mispair" {
    run gh_pr_upstream_is_mispaired '' 'feat/issue-1315'
    [ "$status" -eq 1 ]
}

# ── F-1-2: correctly paired upstream ──────────────────────────────────
@test "F-1-2: upstream == origin/<current> → bare push" {
    run gh_pr_push_action 'feat/issue-1315' 'origin/feat/issue-1315' ''
    assert_success
    assert_output 'push'
}

@test "F-1-2: full symbolic ref form also pairs cleanly → bare push" {
    run gh_pr_push_action 'feat/issue-1315' \
        'refs/remotes/origin/feat/issue-1315' ''
    assert_success
    assert_output 'push'
}

@test "F-1-2: matched pairing is not a mispair (rc=1)" {
    run gh_pr_upstream_is_mispaired 'origin/feat/issue-1315' 'feat/issue-1315'
    [ "$status" -eq 1 ]
}

# ── F-1-3: mispaired upstream (the #1315 bug) ─────────────────────────
@test "F-1-3: upstream origin/main on a feature branch → mispair detected" {
    run gh_pr_upstream_is_mispaired 'origin/main' 'feat/issue-1315'
    assert_success
}

@test "F-1-3: upstream origin/main on a feature branch → push -u origin HEAD" {
    run gh_pr_push_action 'feat/issue-1315' 'origin/main' ''
    assert_success
    assert_output 'push -u origin HEAD'
}

@test "F-1-3: mispaired state must NOT prescribe a bare push" {
    run gh_pr_push_action 'feat/issue-1315' 'origin/main' ''
    assert_success
    refute_output 'push'
    refute_output --partial 'STOP'
}

@test "F-1-3: worktree-created branch tracking refs/remotes/origin/main → push -u" {
    # git worktree add -b <branch> off origin/main leaves this exact state.
    run gh_pr_push_action 'wt/issue-1315/1' 'refs/remotes/origin/main' ''
    assert_success
    assert_output 'push -u origin HEAD'
}

@test "F-1-3: mispair wins over a bogus 'diverged' verdict" {
    # While mispaired, ahead/behind is computed against base, so the
    # divergence signal is unreliable — re-pairing must take precedence.
    run gh_pr_push_action 'feat/issue-1315' 'origin/main' 'diverged'
    assert_success
    assert_output 'push -u origin HEAD'
}

@test "F-1-3: intentionally differently-named tracking branch → push -u (accepted trade-off)" {
    run gh_pr_push_action 'fix' 'origin/hotfix-2026-08' ''
    assert_success
    assert_output 'push -u origin HEAD'
}

# ── F-1-4: diverged upstream (regression guard, pre-existing row) ──────
@test "F-1-4: paired upstream diverged → STOP" {
    run gh_pr_push_action 'feat/issue-1315' 'origin/feat/issue-1315' 'diverged'
    assert_success
    assert_output 'STOP'
}

@test "F-1-4: paired upstream diverged (full ref form) → STOP" {
    run gh_pr_push_action 'feat/issue-1315' \
        'refs/remotes/origin/feat/issue-1315' 'diverged'
    assert_success
    assert_output 'STOP'
}

# ── F-2-0: not on the base branch → untouched normal path ─────────────
@test "F-2-0: on a feature branch → not-on-base" {
    run gh_pr_base_branch_decision 'feat/issue-1315' 'main' 'aaa111' 'aaa111'
    assert_success
    assert_output 'not-on-base'
}

@test "F-2-0: base branch may be a parent PR head ref (stacked PR)" {
    run gh_pr_base_branch_decision 'feat/child' 'feat/parent' '' ''
    assert_success
    assert_output 'not-on-base'
}

# ── F-2-1: on base with local-only commits → auto-branch + rewind ─────
@test "F-2-1: on base, local-only commits not on origin → auto-branch-and-rewind" {
    run gh_pr_base_branch_decision 'main' 'main' \
        $'aaa111\nbbb222' $'aaa111\nbbb222'
    assert_success
    assert_output 'auto-branch-and-rewind'
}

@test "F-2-1: set comparison is order-insensitive" {
    run gh_pr_base_branch_decision 'main' 'main' \
        $'bbb222\naaa111' $'aaa111\nbbb222'
    assert_success
    assert_output 'auto-branch-and-rewind'
}

@test "F-2-1: straggler left on base (sets differ) → warn only, no rewind" {
    run gh_pr_base_branch_decision 'main' 'main' \
        $'aaa111\nbbb222' 'aaa111'
    assert_success
    assert_output 'auto-branch-warn-only'
}

@test "F-2-1: empty local-only range → nothing-to-pr (dirty tree is out of scope)" {
    run gh_pr_base_branch_decision 'main' 'main' '' ''
    assert_success
    assert_output 'nothing-to-pr'
}

# ── F-2-2: commits already pushed to origin/<base> → nothing-to-pr ────
# Step 1b fetches origin before deciding, so commits that already reached
# origin/<base> are excluded from `git rev-list origin/<base>..<base>` — the
# empty-$3 branch IS the "already pushed, stop as before" safety net. There is
# no separate stop-already-pushed decision to test (it was unreachable: the
# A..B range operator already subtracts everything reachable from A).
@test "F-2-2: empty local-only range → nothing-to-pr regardless of moved set" {
    run gh_pr_base_branch_decision 'main' 'main' '' $'aaa111\nbbb222'
    assert_success
    assert_output 'nothing-to-pr'
}

@test "F-2-2: already-pushed state never prescribes an auto-branch or rewind" {
    run gh_pr_base_branch_decision 'main' 'main' '' 'aaa111'
    assert_success
    refute_output --partial 'auto-branch'
    refute_output --partial 'rewind'
}

@test "F-2-2: whitespace-only local-only range is still nothing-to-pr" {
    run gh_pr_base_branch_decision 'main' 'main' $'  \n\t ' 'aaa111'
    assert_success
    assert_output 'nothing-to-pr'
}

# ── F-2-3: branch-name generator, Korean titles ───────────────────────
@test "F-2-3: Korean feat title → type parsed from the ASCII prefix" {
    run gh_pr_commit_type 'feat(devx): 머지된 PR 을 재검증하는 스킬 신설'
    assert_success
    assert_output 'feat'
}

@test "F-2-3: Korean fix title without scope → fix" {
    run gh_pr_commit_type 'fix: 리뷰 반영 및 변수명 오타 수정'
    assert_success
    assert_output 'fix'
}

@test "F-2-3: breaking-change marker still parses the type" {
    run gh_pr_commit_type 'refactor(shell-common)!: 인터페이스 정리'
    assert_success
    assert_output 'refactor'
}

@test "F-2-3: title with no conventional prefix (pure Korean) → chore" {
    run gh_pr_commit_type '한글로만 작성된 커밋 제목'
    assert_success
    assert_output 'chore'
}

@test "F-2-3: unknown ASCII prefix → chore" {
    run gh_pr_commit_type 'wibble: something'
    assert_success
    assert_output 'chore'
}

@test "F-2-3: Korean title + issue number → <type>/issue-<N>" {
    local _type
    _type=$(gh_pr_commit_type 'feat(devx): 머지된 PR 을 재검증하는 스킬 신설')
    run gh_pr_branch_name "$_type" '1315' '20260811' 'bf5b868'
    assert_success
    assert_output 'feat/issue-1315'
}

@test "F-2-3: Korean title without issue number → <type>/<YYYYMMDD>-<short-sha>" {
    local _type
    _type=$(gh_pr_commit_type 'fix: 리뷰 반영 및 변수명 오타 수정')
    run gh_pr_branch_name "$_type" '' '20260811' 'bf5b868'
    assert_success
    assert_output 'fix/20260811-bf5b868'
}

@test "F-2-3: generated branch names are pure ASCII" {
    local _name
    _name=$(gh_pr_branch_name \
        "$(gh_pr_commit_type 'feat(devx): 한글 제목 그대로')" '' '20260811' 'abc1234')
    printf '%s' "$_name" | LC_ALL=C grep -qE '^[A-Za-z0-9/_.-]+$'
}

@test "F-2-3: generator is deterministic (same inputs → same name)" {
    local _a _b
    _a=$(gh_pr_branch_name feat '' '20260811' 'abc1234')
    _b=$(gh_pr_branch_name feat '' '20260811' 'abc1234')
    [ "$_a" = "$_b" ]
    [ "$_a" = 'feat/20260811-abc1234' ]
}

@test "F-2-3: non-numeric issue value falls back to the date form" {
    run gh_pr_branch_name feat 'not-a-number' '20260811' 'abc1234'
    assert_success
    assert_output 'feat/20260811-abc1234'
}

@test "F-2-3: unknown type passed directly to the generator → chore" {
    run gh_pr_branch_name 'bogus' '1315' '20260811' 'abc1234'
    assert_success
    assert_output 'chore/issue-1315'
}

# ── F-3: [remote] threading (#1405) ───────────────────────────────────
# The trailing remote parameter defaults to "origin", so every expectation
# above stays valid; these cases pin both halves of that contract.

@test "F-3-1: omitted remote → push -u origin HEAD (regression zero)" {
    run gh_pr_push_action 'feat/issue-1405' '' ''
    assert_success
    assert_output 'push -u origin HEAD'
}

@test "F-3-1: omitted remote → bare push when correctly paired to origin" {
    run gh_pr_push_action 'feat/issue-1405' 'origin/feat/issue-1405' ''
    assert_success
    assert_output 'push'
}

@test "F-3-1: omitted remote → STOP when paired-and-diverged" {
    run gh_pr_push_action 'feat/issue-1405' 'origin/feat/issue-1405' 'diverged'
    assert_success
    assert_output 'STOP'
}

@test "F-3-1: explicit 'origin' is identical to omitting the argument" {
    local _implicit _explicit
    _implicit=$(gh_pr_push_action 'feat/issue-1405' 'origin/main' '')
    _explicit=$(gh_pr_push_action 'feat/issue-1405' 'origin/main' '' 'origin')
    [ "$_implicit" = "$_explicit" ]
    [ "$_implicit" = 'push -u origin HEAD' ]
}

@test "F-3-2: remote=upstream, no upstream ref → push -u upstream HEAD" {
    run gh_pr_push_action 'feat/issue-1405' '' '' 'upstream'
    assert_success
    assert_output 'push -u upstream HEAD'
}

@test "F-3-2: remote=upstream never emits a literal 'origin'" {
    run gh_pr_push_action 'feat/issue-1405' '' '' 'upstream'
    assert_success
    refute_output --partial 'origin'
}

@test "F-3-3: remote=upstream, upstream/<branch> → not a mispair (rc=1)" {
    run gh_pr_upstream_is_mispaired 'upstream/feat/issue-1405' \
        'feat/issue-1405' 'upstream'
    [ "$status" -eq 1 ]
}

@test "F-3-3: remote=upstream, refs/remotes/upstream/<branch> → not a mispair" {
    run gh_pr_upstream_is_mispaired 'refs/remotes/upstream/feat/issue-1405' \
        'feat/issue-1405' 'upstream'
    [ "$status" -eq 1 ]
}

@test "F-3-3: remote=upstream, paired upstream ref → bare push" {
    run gh_pr_push_action 'feat/issue-1405' \
        'refs/remotes/upstream/feat/issue-1405' '' 'upstream'
    assert_success
    assert_output 'push'
}

@test "F-3-4: remote=upstream, origin/<branch> IS a mispair" {
    run gh_pr_upstream_is_mispaired 'origin/feat/issue-1405' \
        'feat/issue-1405' 'upstream'
    assert_success
}

@test "F-3-4: remote=upstream, refs/remotes/origin/<branch> IS a mispair" {
    run gh_pr_upstream_is_mispaired 'refs/remotes/origin/feat/issue-1405' \
        'feat/issue-1405' 'upstream'
    assert_success
}

@test "F-3-4: remote=upstream, branch still paired to origin → push -u upstream HEAD" {
    run gh_pr_push_action 'feat/issue-1405' 'origin/feat/issue-1405' '' 'upstream'
    assert_success
    assert_output 'push -u upstream HEAD'
}

@test "F-3-4: the same origin ref is NOT a mispair when remote=origin" {
    # Same inputs, different target remote → opposite verdict. This is the
    # whole point of the parameter (#1405).
    run gh_pr_upstream_is_mispaired 'origin/feat/issue-1405' \
        'feat/issue-1405' 'origin'
    [ "$status" -eq 1 ]
}

@test "F-3-5: remote=upstream, paired + diverged → STOP" {
    run gh_pr_push_action 'feat/issue-1405' 'upstream/feat/issue-1405' \
        'diverged' 'upstream'
    assert_success
    assert_output 'STOP'
}

@test "F-3-5: remote=upstream, mispair still wins over diverged" {
    run gh_pr_push_action 'feat/issue-1405' 'origin/feat/issue-1405' \
        'diverged' 'upstream'
    assert_success
    assert_output 'push -u upstream HEAD'
}

@test "F-3-5: empty upstream + remote=fork → push -u fork HEAD (arbitrary name)" {
    run gh_pr_push_action 'wt/issue-1405/1' '' '' 'fork'
    assert_success
    assert_output 'push -u fork HEAD'
}
