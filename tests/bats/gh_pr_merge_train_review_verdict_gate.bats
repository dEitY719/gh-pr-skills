#!/usr/bin/env bats
# tests/bats/gh_pr_merge_train_review_verdict_gate.bats
# The merge train's review verdict gate (dEitY719/dotfiles#1564, umbrella #1527)
# and its sha-freshness F-3 form (#1601), run against the shipped text of
# skills/merge-train/references/review-verdict-gate.md and routing-table.md.
# Fixture: fixtures/gh_pr_merge_train_review_verdict_gate.sh. Moved from
# dEitY719/dotfiles tests/bats/functions/ by dEitY719/dotfiles#2200; the
# predicates' own tests (_gh_pr_merge_train_has_review_*_label,
# _gh_pr_merge_train_review_passed_{marker_sha,stale}) stay with their SSOT in
# dotfiles.

load 'test_helper'

setup() {
    setup_isolated_home
    unset GH_PR_MERGE_TRAIN_TRUSTED_LOGIN
    # shellcheck source=fixtures/gh_pr_merge_train_review_verdict_gate.sh
    source "${FIXTURES}/gh_pr_merge_train_review_verdict_gate.sh"
}

teardown() {
    teardown_isolated_home
}

# gh stub replaying the real `--jq` filter against STUB_COMMENTS_JSON — copied
# with the tests from dotfiles' gh_pr_merge_train_review_verdict_gate.bats.
_freshness_stub() {
    STUB_LOG="${BATS_TEST_TMPDIR}/gh.log"
    : >"$STUB_LOG"
    # STUB_COMMENTS_JSON: a JSON array of `{"user":{"login":...},"body":...}`
    # objects — the real shape `gh api .../comments` answers. Tests set this
    # instead of a flat text blob so author filtering can be exercised
    # faithfully: the stub replays the REAL `--jq` expression the function
    # under test built (with its `select(.user.login == "...")` clause)
    # against this JSON via a real `jq`, rather than re-deriving the filter
    # logic in bash by hand. It is the body of PAGE 1.
    : "${STUB_COMMENTS_JSON:=[]}"
    # STUB_LAST_PAGE: unset or 1 = single-page PR, so the page-1 response
    # carries NO `Link` header at all (the default, which is what every
    # pre-#1615 test here exercises). Set it to N>1 to simulate an N-page PR:
    # the page-1 response then grows a `rel="last"` Link header pointing at
    # page N, and STUB_PAGE_N_COMMENTS_JSON becomes the body served for the
    # page=N call.
    : "${STUB_PAGE_N_COMMENTS_JSON:=[]}"
    # shellcheck disable=SC2317  # invoked indirectly by the function under test
    gh() {
        printf 'gh %s [GH_HOST=%s]\n' "$*" "${GH_HOST-}" >>"$STUB_LOG"
        case "$*" in
        *"/comments"*"--jq"*)
            # Scan positionally — never a fixed index. The real call's flag
            # order has already shifted twice (per_page=100, then `-i -X GET`
            # plus an explicit page), so hardcoding "the 5th arg" silently
            # reads the wrong token the next time flags move.
            _fs_jq_expr=""
            _fs_want_next=0
            _fs_page=1
            _fs_include_headers=0
            for _fs_arg in "$@"; do
                if [ "$_fs_want_next" -eq 1 ]; then
                    _fs_jq_expr="$_fs_arg"
                    _fs_want_next=0
                    continue
                fi
                case "$_fs_arg" in
                --jq) _fs_want_next=1 ;;
                -i) _fs_include_headers=1 ;;
                # `page=N`, not `per_page=N` — the latter starts with `per_`.
                page=*) _fs_page="${_fs_arg#page=}" ;;
                esac
            done

            # STUB_COMMENTS_RC fails EVERY /comments call (page 1 included) —
            # use it to test call-1 failure. STUB_PAGE_N_RC fails ONLY a
            # non-page-1 call, so page 1 can succeed and the last-page call
            # can fail on its own — the two must stay independent, or a test
            # named "last-page call fails" would actually fail at call 1 and
            # never reach the code path it claims to cover (PR #1630 review,
            # codex BLOCKER).
            if [ "$_fs_page" = "1" ]; then
                [ "${STUB_COMMENTS_RC:-0}" -eq 0 ] || return "$STUB_COMMENTS_RC"
            else
                [ "${STUB_PAGE_N_RC:-0}" -eq 0 ] || return "$STUB_PAGE_N_RC"
            fi

            if [ "$_fs_include_headers" -eq 1 ]; then
                # Mirror what real `gh api -i` emits (verified against gh
                # 2.45.0): an LF-terminated status line, CRLF-terminated
                # headers, then a lone-CR blank line before the body.
                printf 'HTTP/1.1 200 OK\n'
                printf 'Content-Type: application/json; charset=utf-8\r\n'
                # Decoy: this header's VALUE contains the word "Link", so a
                # parser that greps for `Link` unanchored reads garbage.
                printf 'Access-Control-Expose-Headers: ETag, Link, Location\r\n'
                if [ "${STUB_LAST_PAGE:-1}" -gt 1 ]; then
                    printf 'Link: <https://api.github.com/repositories/1/issues/11/comments?page=2&per_page=100>; rel="next", '
                    printf '<https://api.github.com/repositories/1/issues/11/comments?page=%s&per_page=100>; rel="last"\r\n' \
                        "$STUB_LAST_PAGE"
                fi
                printf '\r\n'
            fi

            if [ "$_fs_page" = "1" ]; then
                printf '%s' "$STUB_COMMENTS_JSON" | jq -r "$_fs_jq_expr"
            else
                printf '%s' "$STUB_PAGE_N_COMMENTS_JSON" | jq -r "$_fs_jq_expr"
            fi
            return 0
            ;;
        *)
            return "${STUB_GH_RC:-0}"
            ;;
        esac
    }
}

# One comment object for STUB_COMMENTS_JSON. $1=login, $2=body.
_comment() {
    jq -nc --arg login "$1" --arg body "$2" '{user:{login:$login},body:$body}'
}

# ---------------------------------------------------------------------
# The decision table
# ---------------------------------------------------------------------

@test "gate: review-blocked -> [SKIPPED] with the blocking reason" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "gate: no verdict label at all -> [SKIPPED] review not verified" {
    run train_verdict_gate "$(verdict_pr 11 '[]')"
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

# Absence is the third state and it must stay a skip. Merging an unreviewed PR
# is the failure #1527 reproduced (PR #1518 -> #1520 -> PR #1522); a skip is
# one label away from moving.

@test "gate: an unrelated label is still 'not verified'" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"enhancement"},{"name":"ai"}]')"
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

@test "gate: review-passed alone -> stays in the queue" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-passed"}]')"
    assert_success
    assert_output 'proceed'
}

@test "gate: review-passed alongside unrelated labels still proceeds" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"fix"},{"name":"review-passed"}]')"
    assert_success
    assert_output 'proceed'
}

# #1563's invalidation should make this unreachable, but a gate on a merge has
# to be deterministic about a state it does not expect. Blocked wins.

@test "gate: review-blocked beats a stale review-passed" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-passed"},{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "gate: label order does not change the verdict" {
    run train_verdict_gate "$(verdict_pr 11 '[{"name":"review-blocked"},{"name":"review-passed"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

# A `gh pr list` whose --json projection omitted `labels` must read as "not
# verified", never as a pass — the same fail-closed direction as everywhere
# else in this train.

@test "gate: a PR object with no labels field is 'not verified'" {
    run train_verdict_gate '{"number":11,"isDraft":false}'
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

# ---------------------------------------------------------------------
# routing-table.md F-3 — the mid-run re-check
# ---------------------------------------------------------------------
#
# A deferred devx:pr-review-all pass can add or flip a verdict label minutes
# after Step 2 built the queue. F-3's re-query is the only thing that sees it,
# so the verdict rows have to short-circuit the D-1 table the same way
# `reply-pending` does — before `mergeStateStatus` is read at all.

@test "F-3: a mid-run review-blocked short-circuits a CLEAN/MERGEABLE PR" {
    run train_route_short_circuit "$(verdict_pr 11 '[{"name":"review-blocked"}]')"
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "F-3: a mid-run label loss short-circuits a CLEAN/MERGEABLE PR" {
    run train_route_short_circuit "$(verdict_pr 11 '[]')"
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

@test "F-3: review-passed lets the PR reach the D-1 table" {
    # The shipped re-check also runs the #1601 freshness lookup, so the label
    # needs a fresh marker from the trusted login to get through.
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    run train_route_short_circuit "$(verdict_pr 11 '[{"name":"review-passed"}]')"
    assert_success
    assert_output 'proceed'
}

# Order among the short-circuits: draft and reply-pending are answered first,
# so their (more specific) reasons are what the report shows.

@test "F-3: draft outranks the verdict gate in the reason it reports" {
    run train_route_short_circuit "$(verdict_pr 11 '[{"name":"review-blocked"}]' true)"
    assert_success
    assert_output 'skip:draft'
}

@test "F-3: reply-pending outranks the verdict gate in the reason it reports" {
    run train_route_short_circuit \
        "$(verdict_pr 11 '[{"name":"reply-pending"},{"name":"review-blocked"}]')"
    assert_success
    # The shipped fence prints the bare reason; the table row's longer text
    # ("— review reply not yet complete") is the human-facing gloss.
    assert_output 'skip:reply-pending'
}

@test "independence: the gate then rejects that same PR" {
    run train_verdict_gate '{"number":11,"labels":[{"name":"review-blocked"}]}'
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

# ---------------------------------------------------------------------
# F-3 integration — the full per-PR form (routing-table.md)
# ---------------------------------------------------------------------

@test "F-3 freshness: review-blocked still wins over everything else" {
    _freshness_stub
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-blocked"}]')" acme/widget '' deadbeef bot
    assert_success
    assert_output 'skip:review-blocked — reviewer verdict is blocking'
}

@test "F-3 freshness: no verdict label at all is still 'not verified'" {
    _freshness_stub
    run train_verdict_gate_f3 "$(verdict_pr 11 '[]')" acme/widget '' deadbeef bot
    assert_success
    assert_output 'skip:review not verified — no review-passed label'
}

@test "F-3 freshness: a fresh review-passed marker from the expected login proceeds" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef bot
    assert_success
    assert_output 'proceed'
}

@test "F-3 freshness: a stale review-passed (head advanced) is skipped" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:0000000 -->')" '[$c]')
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef bot
    assert_success
    assert_output 'skip:review-passed label stale — head advanced without invalidation'
}

@test "F-3 freshness: a review-passed label with NO marker at all is skipped WITHOUT dropping it" {
    # A pre-#1601 label, a manual push, or a repo that never wired the
    # writer all look like this. Absence alone is not proof the label is
    # wrong for this head (agy, PR #1608 review, both rounds) — route as
    # unverified, but never delete on a guess.
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot 'plain comment, no marker')" '[$c]')
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef bot
    assert_success
    assert_output 'skip:review-passed not confirmed for this head — no freshness marker found'
    run cat "$STUB_LOG"
    refute_output --partial 'DELETE'
}

@test "F-3 freshness (BLOCKER fix): a review-passed label with only a FORGED marker is skipped WITHOUT dropping it" {
    # The exact PR #1608 review finding: a non-pipeline commenter's marker
    # must never re-arm a label the gate would otherwise (correctly) skip —
    # and it must not count as evidence of staleness either. To the trusted
    # login's check this looks exactly like ABSENT, not MISMATCH, so it must
    # not trigger the self-heal delete.
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment attacker '<!-- review-verdict:review-passed:deadbeef -->')" '[$c]')
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef bot
    assert_success
    assert_output 'skip:review-passed not confirmed for this head — no freshness marker found'
    run cat "$STUB_LOG"
    refute_output --partial 'DELETE'
}

@test "F-3 freshness: a MISMATCH PR self-heals by dropping the label" {
    _freshness_stub
    STUB_COMMENTS_JSON=$(jq -nc --argjson c "$(_comment bot '<!-- review-verdict:review-passed:0000000 -->')" '[$c]')
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef bot
    run cat "$STUB_LOG"
    assert_output --partial 'api -X DELETE repos/acme/widget/issues/11/labels/review-passed'
}

@test "F-3 freshness (BLOCKER fix): an UNDETERMINED lookup failure is skipped WITHOUT dropping the label" {
    # The exact PR #1608 review finding: a transient gh api failure must
    # never destroy an otherwise-valid review-passed label.
    _freshness_stub
    STUB_COMMENTS_RC=1
    run train_verdict_gate_f3 "$(verdict_pr 11 '[{"name":"review-passed"}]')" acme/widget '' deadbeef bot
    assert_success
    assert_output 'skip:review-passed freshness unknown — marker lookup failed, treating as unverified'
    run cat "$STUB_LOG"
    refute_output --partial 'DELETE'
}

# ---------------------------------------------------------------------
# Drift guards — the label-only mirror and the draft row
# ---------------------------------------------------------------------

@test "drift: both label-only skip reasons are still the shipped strings" {
    run grep -cF -e '[SKIPPED] review-blocked — reviewer verdict is blocking' \
        -e '[SKIPPED] review not verified — no review-passed label' "$VERDICT_DOC"
    [ "$output" -ge 2 ]
}

@test "drift: routing-table.md still tables the draft short-circuit first" {
    run grep -F '| `isDraft == true` | `[SKIPPED] draft` |' "$ROUTING_DOC"
    assert_success
}
