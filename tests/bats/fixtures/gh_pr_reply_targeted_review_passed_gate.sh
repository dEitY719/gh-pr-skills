#!/usr/bin/env bash
# tests/bats/fixtures/gh_pr_reply_targeted_review_passed_gate.sh
# gh-pr:reply Step 6's `review-passed` gate (dEitY719/dotfiles#1636), end to
# end. Moved from dEitY719/dotfiles tests/bats/functions/_fixtures/ by
# dEitY719/dotfiles#2200 — the half that tests the skill text.
#
# The vendored helpers are sourced directly (the loader in fence 1 of
# review-passed-gate.md is the tier ladder, tested by tests/plugin-root-tier5.sh),
# and the ORDER of the step is run from the shipped text:
#   * history + evidence + merge + ledger + gate: ```bash fence 2 of
#     skills/reply/references/review-passed-gate.md, minus its `HEAD_SHA=$(gh
#     pr view …)` read — the test supplies the post-push head instead;
#   * apply: ```bash fence 3 of the same file.
# The one step not in that doc is the invalidation drop, which the skill runs
# from skills/reply/lib/step6-board-and-labels.sh --phase pre-gate BEFORE the
# gate; it is mirrored here as that script's single `_gh_pr_drop_label` call.
# shellcheck disable=SC2034,SC1091  # vars are read by the eval'd shipped blocks or the .bats; sources resolve at run time

GATE_DOC="${REPO_ROOT}/skills/reply/references/review-passed-gate.md"
_V="${REPO_ROOT}/lib/vendor/shell-common/functions"
# shellcheck source=/dev/null
. "$_V/gh_pr_reply_targeted_review.sh"
# shellcheck source=/dev/null
. "$_V/devx_pr_review_all.sh"
# shellcheck source=/dev/null
. "$_V/gh_pr_edit_safe.sh"
unset _V

# Usage: <this pass's origin lines> | pr_reply_step6 <pr> <repo> <host> <head-sha>
#            [<pushed-fixes>]          # default 1
#            [<comments-json-file>]    # default: no comments -> no evidence
#            [<expected-login>]        # default: pipeline-bot
pr_reply_step6() {
    local PR_NUMBER="$1" TARGET_REPO="$2" TARGET_HOST="$3" HEAD_SHA="$4" _pushed="${5-1}" \
        COMMENT_JSON="${6-}" ME="${7-pipeline-bot}"
    local ORIGINS HISTORY EVIDENCE MERGED DECISION _gate _apply

    ORIGINS=$(cat)

    # step6-board-and-labels.sh --phase pre-gate: drop the stale label first.
    if [ "$_pushed" -gt 0 ]; then
        _gh_pr_drop_label "$PR_NUMBER" review-passed "$TARGET_REPO" "$TARGET_HOST" >/dev/null 2>&1 || :
    fi

    if [ -z "$COMMENT_JSON" ] || [ ! -r "$COMMENT_JSON" ]; then
        COMMENT_JSON="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/no-comments.json"
        printf '[]\n' >"$COMMENT_JSON"
    fi

    _gate=$(fence_block "$GATE_DOC" 2 | sed '/^HEAD_SHA=/,/headRefOid)$/d')
    _apply=$(fence_block "$GATE_DOC" 3)
    eval "$_gate"
    eval "$_apply"
}
