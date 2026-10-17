#!/usr/bin/env bats
# tests/bats/gh_pr_reply_targeted_review_passed_gate.bats
# dEitY719/dotfiles#1636 — gh-pr:reply Step 6's `review-passed` gate, end to
# end, run from the shipped skills/reply/references/review-passed-gate.md
# (fixture: fixtures/gh_pr_reply_targeted_review_passed_gate.sh). Moved from
# dEitY719/dotfiles tests/bats/functions/ by dEitY719/dotfiles#2200; the
# doc-guards on dotfiles' gh_pr_edit_safe.sh and the has_review predicate
# tests stay there with their SSOT.
#
# Supersedes gh_pr_reply_targeted_rereview.bats (#1616), whose subject — a
# scoped `gh:pr-review` re-call that had to return a non-blocking verdict
# before `review-passed` could be written — no longer exists. Those tests are
# REWRITTEN here rather than dropped: they pinned NF-2's "never self-certify"
# rule, which #1636 deliberately relaxed on this one path, so the file now
# pins the new policy explicitly instead of silently losing the old one.
#
# The fixture does NOT re-implement the gate — it sources the vendored
# lib/vendor/shell-common/lib/{gh_pr_reply_targeted_review,devx_pr_review_all}.sh
# and evals the doc's own blocks, so a mirror cannot pass while either drifts
# (dEitY719/dotfiles#1524's rule).
#
# Acceptance criteria from the issue, in order:
#   AC-1 all comments replied, no unresolved BLOCKER -> review-passed applied
#        (freshness marker included), with NO external CLI re-call
#   AC-2 no BLOCKER item at all -> review-passed applied
#   AC-3 one unresolved BLOCKER -> review-passed NOT applied, nothing written
#   AC-4 review-passed is still invalidated on every push (unchanged rule)
#   AC-5 the label write stays soft-fail

load 'test_helper'

setup() {
    setup_isolated_home
    GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
    : >"$GH_LOG"
    export GH_LOG
    # PR #1637 review, agy BLOCKER: the gate now refuses to certify a PR no
    # external reviewer ever looked at, and the evidence default is
    # fail-closed. Every pre-existing test in this file describes a PR that HAS
    # been reviewed — that review is what produced the origin lines — so they
    # hand the fixture a comment dump carrying an `ai-review` marker. The
    # no-evidence case has tests of its own below.
    #
    # Since #1639 that dump is the RAW comments JSON (`.user.login` intact),
    # not body text, and the readers only trust the pipeline's own login —
    # so the fixture attributes the reviewer comment to `pipeline-bot`, the
    # login `pr_reply_step6` asks as by default.
    REVIEWED_TXT="${BATS_TEST_TMPDIR}/bodies_reviewed.md"
    printf '%s\n' \
        '<!-- ai-review:codex:newsha -->' \
        'Verdict: BLOCKING' \
        '<!-- /ai-review:codex:newsha -->' >"$REVIEWED_TXT"
    export REVIEWED_TXT
    REVIEWED_BODIES="${BATS_TEST_TMPDIR}/comments_reviewed.json"
    jq -Rs '[{user: {login: "pipeline-bot"}, body: .}]' \
        <"$REVIEWED_TXT" >"$REVIEWED_BODIES"
    export REVIEWED_BODIES
    unset GH_PR_REPLY_TRUSTED_LOGIN
    # shellcheck source=fixtures/gh_pr_reply_targeted_review_passed_gate.sh
    source "${FIXTURES}/gh_pr_reply_targeted_review_passed_gate.sh"
    # shellcheck disable=SC2317  # called indirectly by the helpers under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        return 0
    }
    # shellcheck disable=SC2317  # called indirectly by the helpers under test
    _gh_pr_edit_safe_label() {
        printf 'add %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        return "${STUB_ADD_RC:-0}"
    }
}

teardown() {
    teardown_isolated_home
}

# The PR #1609 shape: codex raised (and got) 2 BLOCKER fixes, agy raised 3
# non-blocking FOLLOW-UPs that were all validly declined.
_origins_1609() {
    printf '%s\n' \
        codex:BLOCKER:ACCEPT \
        codex:BLOCKER:ACCEPT \
        agy:FOLLOW-UP:DECLINE \
        agy:FOLLOW-UP:DECLINE \
        agy:FOLLOW-UP:DECLINE
}

# ---------------------------------------------------------------------
# AC-1 — the pass path
# ---------------------------------------------------------------------

@test "AC-1: a non-blocking reviewer's DECLINE no longer pins review-blocked" {
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 1 "$REVIEWED_BODIES"
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1609/labels/review-blocked'
}

@test "AC-1: every BLOCKER resolved -> review-passed is applied" {
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 1 "$REVIEWED_BODIES"
    run cat "$GH_LOG"
    assert_output --partial 'add 1609 review-passed --repo acme/widget'
}

# The whole point of #1636: the label is re-earned without paying for an
# external reviewer round-trip. Nothing in this path may shell out to a CLI.

@test "AC-1 (#1636): no reviewer CLI and no gh:pr-review call is made" {
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 1 "$REVIEWED_BODIES"
    run cat "$GH_LOG"
    refute_output --partial '--ai '
    refute_output --partial '--paths'
    refute_output --partial 'pr-review'
    refute_output --partial 'pr diff'
}

@test "AC-1 (NF-1): the label carries the POST-push head sha as its freshness marker" {
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 1 "$REVIEWED_BODIES"
    run cat "$GH_LOG"
    assert_output --partial 'review-verdict:review-passed:newsha'
}

@test "AC-1: every gh call pins the target host (#1403 / #1407)" {
    _origins_1609 | pr_reply_step6 1609 acme/widget ghe.example.com newsha 1 "$REVIEWED_BODIES"
    run grep -c 'GH_HOST=ghe.example.com' "$GH_LOG"
    assert_success
    refute_output '0'
}

@test "AC-1: the reported line says the label was earned without a re-review" {
    run bash -c "
        $(declare -f fence_block)
        REPO_ROOT='${REPO_ROOT}'
        . '${FIXTURES}/gh_pr_reply_targeted_review_passed_gate.sh'
        gh() { return 0; }
        _gh_pr_edit_safe_label() { return 0; }
        printf '%s\n' codex:BLOCKER:ACCEPT | pr_reply_step6 1609 acme/widget '' newsha 1 '$REVIEWED_BODIES'"
    assert_success
    assert_output --partial 'review-passed 적용'
    assert_output --partial '외부 재검토 없음'
}

# ---------------------------------------------------------------------
# AC-2 — nothing blocked in the first place
# ---------------------------------------------------------------------

@test "AC-2: a PR whose comments were all non-blocking earns review-passed" {
    printf '%s\n' agy:FOLLOW-UP:DECLINE agy:Suggestion:ACCEPT |
        pr_reply_step6 1609 acme/widget '' newsha 1 "$REVIEWED_BODIES"
    run cat "$GH_LOG"
    assert_output --partial 'add 1609 review-passed'
}

@test "AC-2: ACCEPT-PARTIAL on a BLOCKER counts as resolved" {
    printf '%s\n' codex:BLOCKER:ACCEPT-PARTIAL |
        pr_reply_step6 1609 acme/widget '' newsha 1 "$REVIEWED_BODIES"
    run cat "$GH_LOG"
    assert_output --partial 'add 1609 review-passed'
}

# ---------------------------------------------------------------------
# AC-3 — the fail-closed half, unchanged by the relaxation
# ---------------------------------------------------------------------

@test "AC-3: a DECLINEd BLOCKER never adds review-passed" {
    printf '%s\n' codex:BLOCKER:ACCEPT codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget '' newsha
    run cat "$GH_LOG"
    refute_output --partial 'add 1609 review-passed'
}

@test "AC-3: a QUESTION on a BLOCKER never adds review-passed" {
    printf '%s\n' codex:BLOCKER:QUESTION |
        pr_reply_step6 1609 acme/widget '' newsha
    run cat "$GH_LOG"
    refute_output --partial 'add 1609 review-passed'
}

@test "AC-3: an unresolved BLOCKER leaves review-blocked untouched" {
    printf '%s\n' codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget '' newsha
    run cat "$GH_LOG"
    refute_output --partial 'labels/review-blocked'
}

@test "AC-3: the report says the label is held and names the reviewer" {
    run bash -c "
        $(declare -f fence_block)
        REPO_ROOT='${REPO_ROOT}'
        . '${FIXTURES}/gh_pr_reply_targeted_review_passed_gate.sh'
        gh() { return 0; }
        _gh_pr_edit_safe_label() { return 0; }
        printf '%s\n' codex:BLOCKER:DECLINE | pr_reply_step6 1609 acme/widget '' newsha"
    assert_success
    assert_output --partial 'codex'
    assert_output --partial 'review-blocked 유지'
    assert_output --partial 'review-passed 미부여'
}

@test "AC-3: no freshness marker is posted when the gate holds" {
    printf '%s\n' codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget '' newsha
    run cat "$GH_LOG"
    refute_output --partial 'review-verdict:review-passed'
}

# ---------------------------------------------------------------------
# AC-4 — the #1563 invalidation rule is unchanged
# ---------------------------------------------------------------------

@test "AC-4: review-passed is still invalidated on every push" {
    printf '%s\n' codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget ghe.example.com newsha
    run cat "$GH_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/1609/labels/review-passed'
}

# Order matters: the invalidation drop runs BEFORE the gate re-applies, or the
# skill would delete the label it just earned.

@test "AC-4: the invalidation drop precedes the re-apply" {
    _origins_1609 | pr_reply_step6 1609 acme/widget '' newsha 1 "$REVIEWED_BODIES"
    run bash -c "grep -n 'labels/review-passed\|add 1609 review-passed' '$GH_LOG' | head -2 | tr '\n' '|'"
    assert_output --partial 'DELETE'
    run bash -c "grep -n 'review-passed' '$GH_LOG' | head -1"
    assert_output --partial 'DELETE'
}

@test "AC-4: with no push there is no invalidation, and the gate still runs" {
    _origins_1609 | pr_reply_step6 1609 acme/widget '' newsha 0 "$REVIEWED_BODIES"
    run cat "$GH_LOG"
    refute_output --partial 'DELETE repos/acme/widget/issues/1609/labels/review-passed'
    assert_output --partial 'add 1609 review-passed'
}

# ---------------------------------------------------------------------
# AC-5 — soft-fail
# ---------------------------------------------------------------------

@test "AC-5: a failing label add warns and leaves the PR unlabelled, rc 0" {
    run bash -c "
        $(declare -f fence_block)
        REPO_ROOT='${REPO_ROOT}'
        . '${FIXTURES}/gh_pr_reply_targeted_review_passed_gate.sh'
        gh() { return 0; }
        _gh_pr_edit_safe_label() { return 1; }
        printf '%s\n' codex:BLOCKER:ACCEPT | pr_reply_step6 1609 acme/widget '' newsha 1 '$REVIEWED_BODIES'"
    assert_success
    assert_output --partial '미검증으로 취급'
}

@test "AC-5: a missing label in the repo points at gh:label-bootstrap" {
    run bash -c "
        $(declare -f fence_block)
        REPO_ROOT='${REPO_ROOT}'
        . '${FIXTURES}/gh_pr_reply_targeted_review_passed_gate.sh'
        gh() { return 0; }
        _gh_pr_edit_safe_label() { return 3; }
        printf '%s\n' codex:BLOCKER:ACCEPT | pr_reply_step6 1609 acme/widget '' newsha 1 '$REVIEWED_BODIES'"
    assert_success
    assert_output --partial 'gh:label-bootstrap'
}

# ---------------------------------------------------------------------
# PR #1637 review — the two holes in #1636's relaxation
# ---------------------------------------------------------------------

# codex BLOCKER: Step 2's "already replied" dedup filters an earlier pass's
# thread out of every LATER pass, so a pass that declined a BLOCKER left no
# trace in the next pass's ORIGINS — which then read `pass=no-blocker` and
# certified a PR whose blocker was never fixed. The ledger comment is the
# cross-pass memory that closes it.

@test "cross-pass (PR #1637 review, codex BLOCKER): pass 1's DECLINEd BLOCKER still holds pass 2" {
    # Pass 1: codex raises a BLOCKER, it is DECLINEd, the gate holds.
    printf '%s\n' codex:BLOCKER:DECLINE agy:FOLLOW-UP:ACCEPT |
        pr_reply_step6 1609 acme/widget '' newsha 1 "$REVIEWED_BODIES" >/dev/null

    # Pass 1's ledger comment is now one of the PR's comments — posted, like
    # the reviewer's, by the pipeline's own login (#1639).
    local _bodies="${BATS_TEST_TMPDIR}/comments_pass2.json"
    cat "$REVIEWED_TXT" "$GH_LOG" |
        jq -Rs '[{user: {login: "pipeline-bot"}, body: .}]' >"$_bodies"
    : >"$GH_LOG"

    # Pass 2 sees only the agy FOLLOW-UP — the codex thread was deduped away.
    printf '%s\n' agy:FOLLOW-UP:ACCEPT |
        pr_reply_step6 1609 acme/widget '' newsha 1 "$_bodies" >"${BATS_TEST_TMPDIR}/out2"
    run cat "$GH_LOG"
    refute_output --partial 'add 1609 review-passed'
    run cat "${BATS_TEST_TMPDIR}/out2"
    assert_output --partial 'codex'
    assert_output --partial 'review-passed 미부여'
}

# agy BLOCKER: with an EMPTY external-review record, the "external AI FINDS,
# gh:pr-reply CONFIRMS" division of labour has no finder half at all.

@test "evidence (PR #1637 review, agy BLOCKER): a PR no reviewer ever looked at earns nothing" {
    printf '%s\n' agy:FOLLOW-UP:DECLINE |
        pr_reply_step6 1609 acme/widget '' newsha 0 >"${BATS_TEST_TMPDIR}/out"
    run cat "$GH_LOG"
    refute_output --partial 'add 1609 review-passed'
    refute_output --partial 'review-verdict:review-passed'
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial '외부 리뷰 근거'
    assert_output --partial 'review-passed 미부여'
}

# The ledger is written BEFORE the gate and regardless of its outcome: the
# hold case is exactly when the next pass needs to be told.

@test "ledger (PR #1637 review): the origin ledger is posted on the hold path too" {
    printf '%s\n' codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget '' newsha 1 "$REVIEWED_BODIES" >/dev/null
    run cat "$GH_LOG"
    assert_output --partial 'pr-reply-origins:newsha'
    assert_output --partial 'codex:BLOCKER:DECLINE'
    refute_output --partial 'add 1609 review-passed'
}

# ---------------------------------------------------------------------
# #1639 — marker authorship, end to end through Step 6
# ---------------------------------------------------------------------
#
# Both inputs the gate reads out of the comment dump are plain comment text
# anyone who can see the PR can post. These prove the whole Step 6 path, not
# just the parsers, refuses a forged one.

@test "authorship (#1639): a forged ai-review marker does not manufacture evidence" {
    # The cheapest possible unlock: one outsider comment containing the
    # literal marker string used to satisfy the external-review probe.
    local _bodies="${BATS_TEST_TMPDIR}/comments_forged_evidence.json"
    jq -Rs '[{user: {login: "attacker"}, body: .}]' \
        <"$REVIEWED_TXT" >"$_bodies"

    printf '%s\n' agy:FOLLOW-UP:ACCEPT |
        pr_reply_step6 1609 acme/widget '' newsha 1 "$_bodies" >"${BATS_TEST_TMPDIR}/out"
    run cat "$GH_LOG"
    refute_output --partial 'add 1609 review-passed'
    run cat "${BATS_TEST_TMPDIR}/out"
    assert_output --partial '외부 리뷰 근거'
    assert_output --partial 'review-passed 미부여'
}

@test "authorship (#1639): the identical marker from the trusted login still certifies" {
    # Positive control for the test above — the ONLY difference is the author.
    printf '%s\n' agy:FOLLOW-UP:ACCEPT |
        pr_reply_step6 1609 acme/widget '' newsha 1 "$REVIEWED_BODIES" >/dev/null
    run cat "$GH_LOG"
    assert_output --partial 'add 1609 review-passed'
}

@test "authorship (#1639): a forged ledger cannot clear a trusted DECLINE" {
    # Pass 1 legitimately DECLINEs a BLOCKER, so the ledger holds the gate.
    printf '%s\n' codex:BLOCKER:DECLINE |
        pr_reply_step6 1609 acme/widget '' newsha 1 "$REVIEWED_BODIES" >/dev/null

    # An outsider then posts a ledger of their own claiming it was ACCEPTed.
    # Last-block-wins would take it if authorship were not checked.
    local _bodies="${BATS_TEST_TMPDIR}/comments_forged_ledger.json"
    jq -nc \
        --argjson reviewed "$(jq -Rs '{user: {login: "pipeline-bot"}, body: .}' <"$REVIEWED_TXT")" \
        --argjson ledger "$(jq -Rs '{user: {login: "pipeline-bot"}, body: .}' <"$GH_LOG")" \
        --arg forged '<!-- pr-reply-origins:newsha -->
codex:BLOCKER:ACCEPT
<!-- /pr-reply-origins:newsha -->' \
        '[$reviewed, $ledger, {user: {login: "attacker"}, body: $forged}]' >"$_bodies"
    : >"$GH_LOG"

    # Pass 2 says nothing about codex — only the ledger can speak for it.
    printf '%s\n' agy:FOLLOW-UP:ACCEPT |
        pr_reply_step6 1609 acme/widget '' newsha 1 "$_bodies" >"${BATS_TEST_TMPDIR}/out2"
    run cat "$GH_LOG"
    refute_output --partial 'add 1609 review-passed'
    run cat "${BATS_TEST_TMPDIR}/out2"
    assert_output --partial 'codex'
    assert_output --partial 'review-passed 미부여'
}
