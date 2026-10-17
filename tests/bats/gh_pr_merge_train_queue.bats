#!/usr/bin/env bats
# tests/bats/gh_pr_merge_train_queue.bats
# The merge-queue path (dEitY719/dotfiles#1707, PR dEitY719/dotfiles#1725), run
# against the shipped text of skills/merge/references/merge-queue.md and
# skills/merge-train/references/{strict-mode-relaxation,finalize-sweep}.md.
# Fixture: fixtures/gh_pr_merge_train_queue.sh. Moved from dEitY719/dotfiles
# tests/bats/functions/ by dEitY719/dotfiles#2219; the predicates' own tests
# stay with their SSOT in dotfiles (gh_pr_merge_train_queue.bats there).

load 'test_helper'

setup() {
    setup_isolated_home
    GH_LOG="${BATS_TEST_TMPDIR}/gh.log"
    FINALIZE_LOG="${BATS_TEST_TMPDIR}/finalize.log"
    : >"$GH_LOG"
    : >"$FINALIZE_LOG"
    export GH_LOG FINALIZE_LOG
    # shellcheck source=fixtures/gh_pr_merge_train_queue.sh
    source "${FIXTURES}/gh_pr_merge_train_queue.sh"
}

teardown() {
    teardown_isolated_home
    unset -f gh 2>/dev/null || true
}

# --------------------------------------------------------------------------
# gh:pr-merge Step 3 — the `--auto` command
# --------------------------------------------------------------------------

_stub_gh_merge_ok() {
    # shellcheck disable=SC2317  # called indirectly
    gh() {
        printf 'gh %s\n' "$*" >>"$GH_LOG"
        return 0
    }
}

# `--auto` is refused — the state of any repo with allow_auto_merge=false,
# which is dEitY719/dotfiles today. The plain merge must still happen.
_stub_gh_auto_refused() {
    # shellcheck disable=SC2317  # called indirectly
    gh() {
        printf 'gh %s\n' "$*" >>"$GH_LOG"
        case "$*" in
        *--auto*)
            printf 'Auto merge is not allowed for this repository\n' >&2
            return 1
            ;;
        esac
        return 0
    }
}

# Both forms fail — a genuinely unmergeable PR. The SECOND failure is the one
# that surfaces, i.e. exactly what the pre-dEitY719/dotfiles#1707 skill would have reported.
_stub_gh_both_fail() {
    # shellcheck disable=SC2317  # called indirectly
    gh() {
        printf 'gh %s\n' "$*" >>"$GH_LOG"
        printf 'Pull request is not mergeable\n' >&2
        return 1
    }
}

@test "step3: --auto is in the merge command" {
    _stub_gh_merge_ok
    run merge_step3_auto 51 acme/widget github.com --rebase
    assert_success
    run cat "$GH_LOG"
    assert_output --partial 'pr merge 51 --repo acme/widget --rebase --delete-branch --auto'
}

@test "step3: --delete-branch survives the --auto form" {
    _stub_gh_merge_ok
    merge_step3_auto 51 acme/widget github.com --rebase
    run cat "$GH_LOG"
    assert_output --partial '--delete-branch'
}

@test "step3: the strategy flag is passed through unchanged, never swapped" {
    _stub_gh_merge_ok
    merge_step3_auto 51 acme/widget github.com --squash
    run cat "$GH_LOG"
    assert_output --partial '--squash --delete-branch --auto'
    refute_output --partial '--rebase'
}

@test "step3: a successful --auto never runs the plain merge too" {
    _stub_gh_merge_ok
    merge_step3_auto 51 acme/widget github.com --rebase
    run bash -c "grep -c 'pr merge' '$GH_LOG'"
    assert_output "1"
}

@test "step3: a refused --auto falls back to the plain merge" {
    # The load-bearing backward-compatibility guarantee: on a repo where
    # auto-merge is not available, the flag must be a no-op, not a breakage.
    _stub_gh_auto_refused
    run merge_step3_auto 51 acme/widget github.com --rebase
    assert_success
    run cat "$GH_LOG"
    assert_output --partial '--rebase --delete-branch --auto'
    assert_output --partial 'pr merge 51 --repo acme/widget --rebase --delete-branch'
}

@test "step3: the fallback merge carries no --auto" {
    _stub_gh_auto_refused
    merge_step3_auto 51 acme/widget github.com --rebase
    run bash -c "grep -c -- '--auto' '$GH_LOG'"
    assert_output "1"
}

@test "step3: the fallback says why it retried" {
    _stub_gh_auto_refused
    run merge_step3_auto 51 acme/widget github.com --rebase
    assert_output --partial '[INFO] gh-pr:merge: --auto refused'
    assert_output --partial 'retrying the plain merge'
    assert_output --partial 'Auto merge is not allowed'
}

@test "step3: when both forms fail the failure is not swallowed" {
    _stub_gh_both_fail
    run merge_step3_auto 51 acme/widget github.com --rebase
    assert_failure
}

@test "step3: the target host is pinned on both attempts (dEitY719/dotfiles#1403 / dEitY719/dotfiles#1407)" {
    # shellcheck disable=SC2317  # called indirectly
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$GH_LOG"
        case "$*" in
        *--auto*) return 1 ;;
        esac
        return 0
    }
    merge_step3_auto 51 acme/widget ghe.example.com --rebase
    run bash -c "grep -c 'GH_HOST=ghe.example.com' '$GH_LOG'"
    assert_output "2"
}

# --------------------------------------------------------------------------
# gh:pr-merge Step 3.5 — the third outcome
# --------------------------------------------------------------------------

# `gh pr view --json state,...` answers OPEN: accepted by the queue, not merged.
_stub_gh_view_state() {
    # A global, not a `local`: the `gh` function below runs after this helper
    # has returned, so a dynamically-scoped local would already be gone.
    FAKE_PR_STATE="$1"
    # shellcheck disable=SC2317  # called indirectly
    gh() {
        printf 'gh %s\n' "$*" >>"$GH_LOG"
        printf '{"state":"%s","mergedAt":null,"headRefName":"wt/issue-1707/1","baseRefName":"main","url":"https://github.com/acme/widget/pull/51"}\n' \
            "$FAKE_PR_STATE"
        return 0
    }
}

@test "step3.5: an OPEN PR after --auto prints the [QUEUED] report" {
    _stub_gh_view_state OPEN
    run merge_step3_5 51 acme/widget github.com
    assert_success
    assert_line --index 0 '[QUEUED] PR #51 added to merge queue — not yet merged'
    assert_line --index 1 '  Branch:  wt/issue-1707/1 → main'
    assert_line --index 2 '  URL:     https://github.com/acme/widget/pull/51'
    [ "${#lines[@]}" -eq 3 ]
}

@test "step3.5: a QUEUED PR runs NONE of the completion sequence" {
    # The whole point: syncing the board, posting ai-metrics, dispatching a
    # post-merge verification or dropping `review-passed` here would all be
    # claims about a merge that has not happened.
    _stub_gh_view_state OPEN
    run merge_step3_5 51 acme/widget github.com
    assert_success
    run cat "$FINALIZE_LOG"
    assert_output ''
}

@test "step3.5: a QUEUED PR is neither [OK] nor [FAIL]" {
    _stub_gh_view_state OPEN
    run merge_step3_5 51 acme/widget github.com
    refute_output --partial '[OK]'
    refute_output --partial '[FAIL]'
}

@test "step3.5: a MERGED PR runs the completion sequence exactly as before" {
    _stub_gh_view_state MERGED
    run merge_step3_5 51 acme/widget github.com
    assert_success
    assert_output --partial '[OK] PR #51 merged'
    run cat "$FINALIZE_LOG"
    assert_output 'finalize:51'
}

@test "step3.5: a CLOSED PR is a failure, not a queue entry" {
    _stub_gh_view_state CLOSED
    run merge_step3_5 51 acme/widget github.com
    assert_output --partial '[FAIL] PR #51 not merged — state is CLOSED'
    run cat "$FINALIZE_LOG"
    assert_output ''
}


# --------------------------------------------------------------------------

# One `repos/{repo}/rules/branches/{base}` response carrying a
# required_status_checks rule with the given strict flag.
_rules_json() {
    printf '[{"type":"pull_request","parameters":{"required_approving_review_count":0}},
             {"type":"required_status_checks","parameters":{
                "strict_required_status_checks_policy":%s,
                "required_status_checks":[{"context":"Lint (mise)"},
                                          {"context":"Shell Lint (mise)"}]}}]' "$1"
}

# One `commits/{base}/check-runs` response.
_checks_json() {
    printf '{"check_runs":[%s]}' "$1"
}

_run_json() {
    printf '{"name":"%s","status":"%s","conclusion":%s}' "$1" "$2" "$3"
}


# --------------------------------------------------------------------------
# Step 3.6 — the per-base guard as a whole
# --------------------------------------------------------------------------

@test "step3.6: relaxed base, green tip -> proceed with the shortcut on" {
    run train_step3_6 main "$(_rules_json false)" \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"success"'),
                          $(_run_json 'Shell Lint (mise)' completed '"success"')")"
    assert_line 'BEHIND_DIRECT=yes'
    refute_output --partial '[SKIPPED]'
}

@test "step3.6: a red required check halts the merge phase for that base" {
    run train_step3_6 main "$(_rules_json false)" \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"failure"')")"
    assert_output --partial '[SKIPPED] main is red'
    assert_output --partial 'halting the merge phase'
}

@test "step3.6: the halt is a SKIP, never a FAILED" {
    # NF-2 leaves no way to clear a [FAILED], so a red base must never produce
    # one — the next tick proceeds the moment main goes green again.
    run train_step3_6 main "$(_rules_json false)" \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"failure"')")"
    refute_output --partial '[FAILED]'
}

@test "step3.6: an unreadable check-runs body halts a RELAXED base" {
    run train_step3_6 main "$(_rules_json false)" ''
    assert_output --partial '[SKIPPED] base health unreadable on main'
}

@test "step3.6: an unreadable check-runs body does NOT halt a strict base" {
    # A base that never relaxed strict mode never depended on this net, and
    # must not start being blocked by a lookup it never needed.
    run train_step3_6 main "$(_rules_json true)" ''
    assert_line 'BEHIND_DIRECT=no'
    refute_output --partial '[SKIPPED]'
}

@test "step3.6: a strict base with a red tip still halts" {
    # The guard is about the base being broken, not about the shortcut.
    run train_step3_6 main "$(_rules_json true)" \
        "$(_checks_json "$(_run_json 'Shell Lint (mise)' completed '"failure"')")"
    assert_output --partial '[SKIPPED] main is red'
}

@test "step3.6: an unreadable rules body cannot enable the shortcut" {
    run train_step3_6 main 'not json' "$(_checks_json "$(_run_json 'Lint (mise)' completed '"success"')")"
    assert_line 'BEHIND_DIRECT=no'
}

# --------------------------------------------------------------------------
# PR dEitY719/dotfiles#1725, codex BLOCKER 2 — a failed RULES lookup must not
# silently disable the red-base safety net (the predicate's own tests stay in
# dotfiles; these drive the shipped Step 3.6 block).
# --------------------------------------------------------------------------

@test "step3.6: BOTH lookups failing halts — the correlated-outage case" {
    # codex FOLLOW-UP #2. Before dEitY719/dotfiles#1725 this printed nothing at all: the first
    # branch needed BEHIND_DIRECT=yes (impossible with unreadable rules) and
    # the elif's base_ci_red is rc 1 on an empty body by its own contract.
    run train_step3_6 main '' ''
    assert_output --partial '[SKIPPED] base health unreadable on main'
}

@test "step3.6: an unreadable rules body alone halts, even with readable checks" {
    # Not defensive padding: with no rules body, BASE_CONTEXTS is empty, so
    # base_ci_red has nothing to match and a red base reads as green.
    run train_step3_6 main '' \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"success"')")"
    assert_output --partial '[SKIPPED] base health unreadable on main'
}

@test "step3.6: a MALFORMED body is as unreadable as a failed call" {
    # `-z` alone only catches the `|| BASE_RULES=''` path. A 200 carrying a
    # proxy interstitial is non-empty, and every predicate reading it answers
    # its own fail-closed rc 1 — which is silence, not a halt. Hence the
    # normalisation to the same empty sentinel.
    run train_step3_6 main 'not json' \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"success"')")"
    assert_output --partial '[SKIPPED] base health unreadable on main'

    run train_step3_6 main "$(_rules_json false)" 'not json either'
    assert_output --partial '[SKIPPED] base health unreadable on main'
}

@test "step3.6: rules unreadable + checks genuinely RED still halts" {
    # The OR must not let a red base through just because the other call failed.
    run train_step3_6 main 'not json' \
        "$(_checks_json "$(_run_json 'Lint (mise)' completed '"failure"')")"
    assert_output --partial '[SKIPPED]'
    refute_output --partial '[FAILED]'
}

@test "step3.6: a confirmed-strict base is still exempt from the unreadable halt" {
    # The preserved rule: a base that never relaxed strict mode never depended
    # on this net and must not start being blocked by a lookup it never needed.
    run train_step3_6 main "$(_rules_json true)" ''
    assert_line 'BEHIND_DIRECT=no'
    refute_output --partial '[SKIPPED]'
}

@test "step3.6: a relaxed base with unreadable checks halts, as before" {
    run train_step3_6 main "$(_rules_json false)" ''
    assert_output --partial '[SKIPPED] base health unreadable on main'
}

@test "step3.6: a base with no required-checks rule halts when checks are unreadable" {
    # It cannot be proven strict, so it is not exempt — and with no contexts
    # the red check could never speak for it either.
    run train_step3_6 main '[{"type":"pull_request","parameters":{}}]' ''
    assert_output --partial '[SKIPPED] base health unreadable on main'
}

@test "step3.6: the halt never depends on BEHIND_DIRECT any more" {
    # BEHIND_DIRECT is the ROUTING answer; conflating it with safety-net
    # eligibility is the bug. Assert the guard does not mention it.
    run grep -F -- '[ "$BEHIND_DIRECT" = yes ] && [ -z "$BASE_CHECKS" ]' "$RELAX_DOC"
    assert_failure
}


@test "step3.5: an unreadable re-read is a failure, not a merge" {
    # shellcheck disable=SC2317  # called indirectly
    gh() { return 1; }
    run merge_step3_5 51 acme/widget github.com
    assert_output --partial '[FAIL] PR #51 not merged — state is unreadable'
    run cat "$FINALIZE_LOG"
    assert_output ''
}

# --------------------------------------------------------------------------
# merge-train Step 0 — the finalize sweep (references/finalize-sweep.md)
# --------------------------------------------------------------------------

@test "step0: only MERGED + review-passed PRs are finalized" {
    run train_step0 '[{"number":51,"title":"a","state":"merged","labels":[{"name":"review-passed"}]},
                      {"number":52,"title":"b","state":"merged","labels":[]},
                      {"number":53,"title":"c","state":"open","labels":[{"name":"review-passed"}]}]'
    assert_success
    assert_output '51'
}

@test "step0: the sweep queries by label, not by recency (PR dEitY719/dotfiles#1725)" {
    train_step0 '[]'
    run cat "$GH_LOG"
    assert_output --partial 'search prs --repo acme/widget --author @me --merged --label review-passed'
    refute_output --partial 'pr list'
}

@test "step0: nothing to finalize prints nothing" {
    run train_step0 '[]'
    assert_success
    assert_output ''
}
