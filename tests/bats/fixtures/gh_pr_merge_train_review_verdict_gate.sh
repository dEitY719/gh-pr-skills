#!/usr/bin/env bash
# tests/bats/fixtures/gh_pr_merge_train_review_verdict_gate.sh
# gh-pr:merge-train's review verdict gate (dEitY719/dotfiles#1564, umbrella
# #1527; sha freshness #1601). Moved from dEitY719/dotfiles
# tests/bats/functions/_fixtures/ by dEitY719/dotfiles#2200 — the half that
# tests the skill text; the predicates' own tests stay with their SSOT there.
#
#   * train_verdict_gate_f3      runs the first ```bash fence of
#                                skills/merge-train/references/review-verdict-gate.md
#   * train_route_short_circuit  runs the second ```bash fence of
#                                skills/merge-train/references/routing-table.md,
#                                behind the table-only draft row (mirrored)
#   * train_verdict_gate         the label-only Step 3.5 prefix — prose in
#                                SKILL.md, so mirrored on the vendored
#                                predicates and pinned by the drift guards
# Both fences load lib/vendor/shell-common through their own tier ladder
# (tier 2, CLAUDE_PLUGIN_ROOT=$REPO_ROOT). Their `[SKIPPED] <reason>` lines are
# reported as `skip:<reason>`, and silence (a fresh PR) as `proceed`.
# shellcheck disable=SC2034,SC1091  # vars are read by the eval'd shipped blocks or the .bats; sources resolve at run time

VERDICT_DOC="${REPO_ROOT}/skills/merge-train/references/review-verdict-gate.md"
ROUTING_DOC="${REPO_ROOT}/skills/merge-train/references/routing-table.md"

# shellcheck source=/dev/null
. "${REPO_ROOT}/lib/vendor/shell-common/functions/gh_pr_merge_train.sh"

# Usage: _verdict_run <doc> <fence#> — eval the shipped block in a subshell
# with the caller's PR_JSON / STATE / N / TARGET_* / HEAD_OID / ME bound.
_verdict_run() {
    local _b _out
    _b=$(fence_block "$1" "$2")
    _out=$(
        unset SHELL_COMMON
        CLAUDE_PLUGIN_ROOT="$REPO_ROOT"
        eval "$_b"
    )
    if [ -z "$_out" ]; then
        printf 'proceed\n'
    else
        printf '%s\n' "$_out" | sed 's/^\[SKIPPED\] /skip:/'
    fi
}

# $1 = PR object (as verdict_pr builds), $2 = repo, $3 = host,
# $4 = current headRefOid, $5 = trusted marker-author login (#1601).
train_verdict_gate_f3() {
    local PR_JSON="$1" TARGET_REPO="$2" TARGET_HOST="$3" HEAD_OID="$4" ME="$5" N
    N=$(printf '%s' "$1" | jq -r '.number')
    _verdict_run "$VERDICT_DOC" 1
}

# $1 = the F-3 `$STATE` blob, $2 = trusted login (default bot). The draft row
# is table-only in routing-table.md; every other row is the shipped fence.
train_route_short_circuit() {
    local STATE="$1" ME="${2-bot}" TARGET_REPO=acme/widget TARGET_HOST='' N
    if printf '%s' "$STATE" | jq -e '.isDraft == true' >/dev/null 2>&1; then
        printf 'skip:draft\n'
        return 0
    fi
    N=$(printf '%s' "$1" | jq -r '.number')
    _verdict_run "$ROUTING_DOC" 2
}

# The label-only Step 3.5 pass. review-blocked is tested FIRST so it wins over
# a stale review-passed; "no label" is a skip, never a pass.
train_verdict_gate() {
    local _pr_json="$1"
    if printf '%s' "$_pr_json" | _gh_pr_merge_train_has_review_blocked_label; then
        printf 'skip:review-blocked — reviewer verdict is blocking\n'
    elif ! printf '%s' "$_pr_json" | _gh_pr_merge_train_has_review_passed_label; then
        printf 'skip:review not verified — no review-passed label\n'
    else
        printf 'proceed\n'
    fi
}

# One `gh pr list --json` element / `gh pr view` blob, for the tests.
# $1 = PR number, $2 = raw JSON labels array, $3 = isDraft (default false).
verdict_pr() {
    printf '{"number":%s,"isDraft":%s,"mergeStateStatus":"CLEAN","mergeable":"MERGEABLE","headRefOid":"deadbeef","labels":%s}' \
        "$1" "${3:-false}" "$2"
}
