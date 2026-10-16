#!/usr/bin/env bats
# tests/bats/gh_pr_merge_train_approval_gate.bats
# Verify the approval-gate classification and the gate-off delegated review of
# gh-pr:merge-train. Fixture: fixtures/gh_pr_merge_train_approval_gate.sh —
# the classifier is fence-extracted from
# skills/merge-train/references/approval-gate.md; the decision-table mirrors
# are pinned by the drift guards at the bottom of this file. Moved from
# dEitY719/dotfiles tests/bats/skills/ by dEitY719/dotfiles#2200.
#
# dEitY719/dotfiles#1519 acceptance criteria:
#   AC-2  403 on both sources        -> gate off, "no policy on <base>"
#   AC-3  ruleset >= 1 + 404 classic -> gate on   (D-2 regression guard)
#   AC-4  5xx / network              -> gate on, fail-closed, named as such
#   AC-5  board not Approved         -> [SKIPPED] self-record withheld (BLOCKER)
#   AC-6  head unchanged since review-> no re-run, [SKIPPED] unchanged
#   AC-7  this suite

load 'test_helper'

setup() {
    setup_isolated_home
    FAKE_PATH_LOG="$(mktemp)"
    export FAKE_PATH_LOG
    # shellcheck source=fixtures/gh_pr_merge_train_approval_gate.sh
    source "${FIXTURES}/gh_pr_merge_train_approval_gate.sh"
}

teardown() {
    teardown_isolated_home
    unset FAKE_RULES_RESPONSE FAKE_RULES_RC FAKE_PROTECTION_RESPONSE FAKE_PROTECTION_RC
    [ -n "${FAKE_PATH_LOG-}" ] && rm -f "$FAKE_PATH_LOG"
    unset FAKE_PATH_LOG
}

plan_403() {
    train_gate_http 403 '{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature."}'
}

# ---------------------------------------------------------------------
# Per-source classification
# ---------------------------------------------------------------------

@test "gate-probe: 403 plan limit is 'no policy', not a lookup failure (#1519)" {
    FAKE_RULES_RESPONSE="$(plan_403)" FAKE_RULES_RC=1
    run _gate_probe "repos/o/r/rules/branches/main" "$_RULES_JQ"
    assert_success
    assert_output 'none'
}

@test "gate-probe: 404 not-configured is 'no policy'" {
    FAKE_RULES_RESPONSE="$(train_gate_http 404 '{"message":"Branch not protected"}')" FAKE_RULES_RC=1
    run _gate_probe "repos/o/r/rules/branches/main" "$_RULES_JQ"
    assert_success
    assert_output 'none'
}

@test "gate-probe: 500 is undetermined -> unknown (stays fail-closed)" {
    FAKE_RULES_RESPONSE="$(train_gate_http 500 '{"message":"Server Error"}')" FAKE_RULES_RC=1
    run _gate_probe "repos/o/r/rules/branches/main" "$_RULES_JQ"
    assert_success
    assert_output 'unknown'
}

@test "gate-probe: no HTTP response at all (network down) -> unknown" {
    FAKE_RULES_RESPONSE='' FAKE_RULES_RC=1
    run _gate_probe "repos/o/r/rules/branches/main" "$_RULES_JQ"
    assert_success
    assert_output 'unknown'
}

@test "gate-probe: 200 with required_approving_review_count=2 -> required count 2" {
    FAKE_RULES_RESPONSE="$(train_gate_http 200 '[{"type":"pull_request","parameters":{"required_approving_review_count":2}}]')"
    run _gate_probe "repos/o/r/rules/branches/main" "$_RULES_JQ"
    assert_success
    assert_output '2'
}

@test "gate-probe: 200 with count=0 is 'no policy' (D-5 unchanged)" {
    FAKE_RULES_RESPONSE="$(train_gate_http 200 '[{"type":"pull_request","parameters":{"required_approving_review_count":0}}]')"
    run _gate_probe "repos/o/r/rules/branches/main" "$_RULES_JQ"
    assert_success
    assert_output 'none'
}

@test "gate-probe: 200 with no pull_request rule is 'no policy'" {
    FAKE_RULES_RESPONSE="$(train_gate_http 200 '[{"type":"deletion"},{"type":"non_fast_forward"}]')"
    run _gate_probe "repos/o/r/rules/branches/main" "$_RULES_JQ"
    assert_success
    assert_output 'none'
}

@test "gate-probe: strictest ruleset wins when several apply" {
    FAKE_RULES_RESPONSE="$(train_gate_http 200 '[{"type":"pull_request","parameters":{"required_approving_review_count":1}},{"type":"pull_request","parameters":{"required_approving_review_count":3}}]')"
    run _gate_probe "repos/o/r/rules/branches/main" "$_RULES_JQ"
    assert_success
    assert_output '3'
}

# ---------------------------------------------------------------------
# Combining the two sources (#1519 F-3, F-4) + #1519 NF-1 header
# ---------------------------------------------------------------------

@test "AC-2: both sources 403 -> gate off with 'no policy on <base>'" {
    FAKE_RULES_RESPONSE="$(plan_403)" FAKE_RULES_RC=1
    FAKE_PROTECTION_RESPONSE="$(plan_403)" FAKE_PROTECTION_RC=1
    run train_gate_verdict main
    assert_success
    assert_output 'off|no policy on main'
}

@test "AC-3: ruleset requires 1, classic 404 -> gate STAYS ON (#1519 D-2 guard)" {
    FAKE_RULES_RESPONSE="$(train_gate_http 200 '[{"type":"pull_request","parameters":{"required_approving_review_count":1}}]')"
    FAKE_PROTECTION_RESPONSE="$(train_gate_http 404 '{"message":"Branch not protected"}')" FAKE_PROTECTION_RC=1
    run train_gate_verdict main
    assert_success
    assert_output 'on|ruleset: 1 approvals'
}

@test "#1519 D-2: classic protection requires 2, ruleset 404 -> gate on via protection" {
    FAKE_RULES_RESPONSE="$(train_gate_http 404 '{"message":"Not Found"}')" FAKE_RULES_RC=1
    FAKE_PROTECTION_RESPONSE="$(train_gate_http 200 '{"required_pull_request_reviews":{"required_approving_review_count":2}}')"
    run train_gate_verdict main
    assert_success
    assert_output 'on|protection: 2 approvals'
}

@test "AC-4: a 5xx on one source -> gate on, header names fail-closed" {
    FAKE_RULES_RESPONSE="$(train_gate_http 502 '{"message":"Bad Gateway"}')" FAKE_RULES_RC=1
    FAKE_PROTECTION_RESPONSE="$(plan_403)" FAKE_PROTECTION_RC=1
    run train_gate_verdict main
    assert_success
    assert_output 'on|fail-closed: main policy unreadable'
}

@test "a concrete requirement outranks an unknown in the header text" {
    FAKE_RULES_RESPONSE="$(train_gate_http 200 '[{"type":"pull_request","parameters":{"required_approving_review_count":1}}]')"
    FAKE_PROTECTION_RESPONSE="$(train_gate_http 500 '{"message":"boom"}')" FAKE_PROTECTION_RC=1
    run train_gate_verdict main
    assert_success
    assert_output 'on|ruleset: 1 approvals'
}

@test "a base with a slash is percent-encoded into BOTH endpoint paths" {
    # Regression guard for PR #1526 review: the header text alone proved
    # nothing about the request. Assert the encoded ref actually reaches the
    # API as one path segment, on the ruleset AND the protection endpoint.
    FAKE_RULES_RESPONSE="$(plan_403)" FAKE_RULES_RC=1
    FAKE_PROTECTION_RESPONSE="$(plan_403)" FAKE_PROTECTION_RC=1
    run train_gate_verdict 'release/2026.08'
    assert_success
    assert_output 'off|no policy on release/2026.08'

    run cat "$FAKE_PATH_LOG"
    assert_output --partial 'repos/o/r/rules/branches/release%2F2026.08'
    assert_output --partial 'repos/o/r/branches/release%2F2026.08/protection'
    refute_output --partial 'branches/release/2026.08'
}

@test "403 permission denial is UNKNOWN, not 'no policy' (fail-closed)" {
    FAKE_RULES_RESPONSE="$(train_gate_http 403 '{"message":"Resource not accessible by personal access token"}')" FAKE_RULES_RC=1
    run _gate_probe "repos/o/r/rules/branches/main" "$_RULES_JQ"
    assert_success
    assert_output 'unknown'
}

@test "403 rate-limit is UNKNOWN, not 'no policy'" {
    FAKE_RULES_RESPONSE="$(train_gate_http 403 '{"message":"API rate limit exceeded for user ID 1."}')" FAKE_RULES_RC=1
    run _gate_probe "repos/o/r/rules/branches/main" "$_RULES_JQ"
    assert_success
    assert_output 'unknown'
}

@test "403 SAML/SSO denial is UNKNOWN, not 'no policy'" {
    FAKE_RULES_RESPONSE="$(train_gate_http 403 '{"message":"Resource protected by organization SAML enforcement."}')" FAKE_RULES_RC=1
    run _gate_probe "repos/o/r/rules/branches/main" "$_RULES_JQ"
    assert_success
    assert_output 'unknown'
}

@test "a permission 403 on ONE source keeps the whole gate on" {
    FAKE_RULES_RESPONSE="$(plan_403)" FAKE_RULES_RC=1
    FAKE_PROTECTION_RESPONSE="$(train_gate_http 403 '{"message":"Must have admin rights to Repository."}')" FAKE_PROTECTION_RC=1
    run train_gate_verdict main
    assert_success
    assert_output 'on|fail-closed: main policy unreadable'
}

@test "2xx with an unparseable body is UNKNOWN, not 'no policy'" {
    FAKE_RULES_RESPONSE="$(train_gate_http 200 '<html>502 upstream</html>')" FAKE_RULES_RC=0
    run _gate_probe "repos/o/r/rules/branches/main" "$_RULES_JQ"
    assert_success
    assert_output 'unknown'
}

@test "2xx with an empty body is UNKNOWN, not 'no policy'" {
    FAKE_RULES_RESPONSE="$(train_gate_http 200 '')" FAKE_RULES_RC=0
    run _gate_probe "repos/o/r/rules/branches/main" "$_RULES_JQ"
    assert_success
    assert_output 'unknown'
}

@test "2xx whose shape shifted (object where an array was expected) is UNKNOWN" {
    FAKE_RULES_RESPONSE="$(train_gate_http 200 '{"message":"Moved Permanently"}')" FAKE_RULES_RC=0
    run _gate_probe "repos/o/r/rules/branches/main" "$_RULES_JQ"
    assert_success
    assert_output 'unknown'
}

# ---------------------------------------------------------------------
# Per-PR routing (approval-gate.md -> "Applying it per PR")
# ---------------------------------------------------------------------

@test "route: gate on + APPROVED -> proceed without a delegated review" {
    run train_pr_route on APPROVED
    assert_success
    assert_output 'proceed'
}

@test "route: gate on + empty reviewDecision -> approval required" {
    run train_pr_route on ''
    assert_success
    assert_output 'skip:approval required (reviewDecision=)'
}

@test "AC-1 precondition: gate off + empty reviewDecision -> delegate" {
    run train_pr_route off ''
    assert_success
    assert_output 'delegate'
}

@test "route: gate off + APPROVED -> proceed, no wasted re-review" {
    run train_pr_route off APPROVED
    assert_success
    assert_output 'proceed'
}

@test "route: gate off + CHANGES_REQUESTED -> skipped before any review runs" {
    run train_pr_route off CHANGES_REQUESTED
    assert_success
    assert_output 'skip:gh-pr:merge refuses reviewDecision=CHANGES_REQUESTED'
}

@test "route: gate off + REVIEW_REQUIRED -> skipped, never delegated" {
    run train_pr_route off REVIEW_REQUIRED
    assert_success
    assert_output 'skip:gh-pr:merge refuses reviewDecision=REVIEW_REQUIRED'
}

# ---------------------------------------------------------------------
# Delegated review (#1519 F-6 … F-9)
# ---------------------------------------------------------------------

@test "AC-6: same head already reviewed -> suppressed" {
    run train_review_suppressed deadbeef deadbeef
    assert_success
}

@test "#1519 F-8: head moved since the last review -> re-review is armed" {
    run train_review_suppressed deadbeef cafebabe
    assert_failure
}

@test "#1519 F-8: no prior review by ME -> not suppressed" {
    run train_review_suppressed '' cafebabe
    assert_failure
}

@test "AC-1: review promoted the card -> proceed to merge" {
    run train_delegated_outcome Approved 1
    assert_success
    assert_output 'proceed'
}

@test "AC-5: review withheld -> SKIPPED with the BLOCKER reason, not merged" {
    run train_delegated_outcome 'In review' 1
    assert_success
    assert_output 'skip:self-record withheld approval (BLOCKER)'
}

@test "AC-6: suppressed re-review reports 'unchanged since review'" {
    run train_delegated_outcome 'In review' 0
    assert_success
    assert_output 'skip:approval withheld (unchanged since review)'
}

@test "already-Approved card from an earlier tick proceeds without re-running" {
    # A PR whose review passed but whose merge then failed on CI comes back
    # with Approved still on the card. Reading the board AFTER the #1519 F-8
    # suppression check is what keeps it moving.
    run train_delegated_outcome Approved 0
    assert_success
    assert_output 'proceed'
}

@test "board unreadable -> fail-closed skip, approval unconfirmed" {
    run train_delegated_outcome '' 1
    assert_success
    assert_output 'skip:board unreadable — approval unconfirmed'
}

@test "#1519 F-9: gh-pr:approve itself failing skips only that PR" {
    run train_delegated_outcome Approved 1 3
    assert_success
    assert_output 'skip:self-record failed'
}

# ---------------------------------------------------------------------
# Doc guards — REMOVED (#1680)
# ---------------------------------------------------------------------
#
# gh-pr-merge-train's SKILL.md and references/ (approval-gate.md, train-loop.md,
# report-format.md, constraints.md, help.md) moved out to their own marketplace
# repo, so the guards that pinned the fixture above to that prose belong there.
# The fixture mirror is real, runnable behaviour and stays — it is simply no
# longer pinned to any doc in this repo.

# ---------------------------------------------------------------------
# Drift guards — every string a decision-table mirror prints must still be
# the one the shipped docs specify.
# ---------------------------------------------------------------------

@test "drift: the classifier really came from approval-gate.md" {
    run declare -f _gate_probe
    assert_output --partial 'Upgrade to GitHub Pro'
    [ -n "$_RULES_JQ" ]
    [ -n "$_PROTECTION_JQ" ]
}

@test "drift: approval-gate.md still states the three header verdicts _gate_combine prints" {
    run grep -cF -e 'on (<source>: <n> approvals)' -e 'on (fail-closed: <base> policy unreadable)' \
        -e 'off (no policy on <base>)' "$APPROVAL_GATE_DOC"
    assert_output '3'
}

@test "drift: approval-gate.md still states both per-PR skip reasons train_pr_route prints" {
    run grep -F '[SKIPPED] approval required (reviewDecision=<value>)' "$APPROVAL_GATE_DOC"
    assert_success
    run grep -F '[SKIPPED] gh-pr:merge refuses reviewDecision=<value>' "$APPROVAL_GATE_DOC"
    assert_success
}

@test "drift: train-loop.md still tables every delegated-review outcome" {
    local s
    for s in 'self-record withheld approval (BLOCKER)' 'approval withheld (unchanged since review)' \
        'board unreadable — approval unconfirmed' 'self-record failed'; do
        grep -qF "[SKIPPED] $s" "$TRAIN_LOOP_DOC" || fail "train-loop.md lost: $s"
    done
}
